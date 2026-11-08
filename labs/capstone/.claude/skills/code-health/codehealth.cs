#:property PublishAot=false
#:package Microsoft.CodeAnalysis.CSharp@5.0.0
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

try { return Run(args); }
catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException
    or InvalidOperationException or System.ComponentModel.Win32Exception)
{
    Console.Error.WriteLine(ex.Message);
    return 2;
}

static int Run(string[] args)
{
    if (args.Length == 0 || args.Contains("--help"))
    {
        Console.WriteLine("codehealth.cs <source-directory> [--format md|json] [--sortie file] [--gate --base ref]");
        return args.Length == 0 ? 2 : 0;
    }
    var directory = Path.GetFullPath(args[0]);
    if (!Directory.Exists(directory)) throw new ArgumentException("Source directory does not exist.");
    string format = "md", baseline = "main";
    string? output = null;
    bool gate = false;
    for (int i = 1; i < args.Length; i++)
    {
        if (args[i] == "--gate") { gate = true; continue; }
        if (i + 1 >= args.Length) throw new ArgumentException("Missing option value.");
        switch (args[i])
        {
            case "--format": format = args[++i]; break;
            case "--sortie": output = args[++i]; break;
            case "--base": baseline = args[++i]; break;
            default: throw new ArgumentException($"Unknown option: {args[i]}");
        }
    }
    if (format is not ("md" or "json")) throw new ArgumentException("Format must be md or json.");
    var root = gate ? Git(Environment.CurrentDirectory, "rev-parse", "--show-toplevel").Trim() : Environment.CurrentDirectory;
    var sources = Directory.EnumerateFiles(directory, "*.cs", SearchOption.AllDirectories)
        .Where(f => !Excluded(f)).Order(StringComparer.Ordinal)
        .ToDictionary(f => Relative(root, f), File.ReadAllText, StringComparer.Ordinal);
    if (sources.Count == 0) throw new ArgumentException("No C# sources found.");
    var current = Analyze(sources);
    var failures = new List<string>();
    if (gate)
    {
        // Read the reference as data; never checkout or execute code from it.
        var reference = Git(root, "rev-parse", "--verify", baseline + "^{commit}").Trim();
        var scope = Relative(root, directory);
        if (scope.StartsWith("..", StringComparison.Ordinal)) throw new ArgumentException("Source must be inside the Git repository.");
        var paths = Git(root, "ls-tree", "-r", "-z", "--name-only", reference, "--", scope)
            .Split('\0', StringSplitOptions.RemoveEmptyEntries)
            .Where(p => p.EndsWith(".cs", StringComparison.Ordinal) && !Excluded(p));
        var previous = Analyze(paths.ToDictionary(p => p, p => Git(root, "show", $"{reference}:{p}"), StringComparer.Ordinal))
            .ToDictionary(f => f.Path, StringComparer.Ordinal);
        foreach (var file in current)
        {
            if (file.Findings.Any(f => f.Severity == "blocking")) failures.Add($"{file.Path}: blocking finding");
            if (previous.TryGetValue(file.Path, out var before))
            {
                if (file.Score < before.Score) failures.Add($"{file.Path}: score {before.Score} -> {file.Score}");
            }
            else if (file.Score < 9) failures.Add($"{file.Path}: new file below 9 ({file.Score})");
        }
    }
    var totalLines = current.Sum(f => f.Lines);
    var average = current.Sum(f => f.Score * f.Lines) / Math.Max(1, totalLines);
    var report = new { files = current, score = Math.Round(average, 2), gate, baseline = gate ? baseline : null, failures };
    var result = format == "json"
        ? JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase })
        : Markdown(current, average, gate, failures);
    if (output is null) Console.WriteLine(result);
    else { Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!); File.WriteAllText(output, result + "\n"); }
    return failures.Count > 0 ? 1 : 0;
}

static bool Excluded(string path) => path.Replace('\\', '/').Split('/').Any(p => p is "bin" or "obj" or "Migrations")
    || path.EndsWith(".g.cs", StringComparison.Ordinal) || path.EndsWith(".Designer.cs", StringComparison.Ordinal);
static string Relative(string root, string path) => Path.GetRelativePath(root, path).Replace('\\', '/');
static string Git(string root, params string[] args)
{
    var start = new ProcessStartInfo("git") { WorkingDirectory = root, RedirectStandardOutput = true, RedirectStandardError = true };
    foreach (var arg in args) start.ArgumentList.Add(arg);
    using var process = Process.Start(start) ?? throw new InvalidOperationException("Cannot run git.");
    var stdout = process.StandardOutput.ReadToEndAsync();
    var stderr = process.StandardError.ReadToEndAsync();
    process.WaitForExit();
    if (process.ExitCode != 0) throw new InvalidOperationException(stderr.GetAwaiter().GetResult());
    return stdout.GetAwaiter().GetResult();
}
static List<FileReport> Analyze(Dictionary<string, string> sources)
{
    var result = new List<FileReport>();
    var duplicateBlocks = new Dictionary<string, (FileReport File, int Index, int Line)>();
    var claimedLines = new Dictionary<(string Path, int Index), string>();
    foreach (var (path, source) in sources.OrderBy(p => p.Key, StringComparer.Ordinal))
    {
        var tree = CSharpSyntaxTree.ParseText(source);
        if (tree.GetDiagnostics().Any(d => d.Severity == DiagnosticSeverity.Error))
            throw new ArgumentException($"Invalid C# syntax: {path}");
        var root = tree.GetRoot();
        // EOF is positioned after the final newline, but does not contain source code.
        var tokens = root.DescendantTokens().Where(t => !t.IsKind(SyntaxKind.EndOfFileToken)).ToArray();
        var codeLines = tokens.Select(t => t.GetLocation().GetLineSpan().StartLinePosition.Line + 1).Distinct().Order().ToArray();
        var file = new FileReport(path, Math.Max(1, codeLines.Length), []);
        result.Add(file);
        void Add(string id, string severity, SyntaxNode node, string message) => AddAt(file, id, severity, Line(node), message);
        var functions = root.DescendantNodes().Where(IsFunction).ToArray();
        if (codeLines.Length >= 600) Add("CH09", codeLines.Length >= 1000 ? "major" : "minor", root, $"{codeLines.Length} code lines");
        if (functions.Length >= 40) Add("CH11", "minor", root, $"{functions.Length} callables");
        foreach (var function in functions)
        {
            var nodes = function.DescendantNodes(n => n == function || !IsFunction(n)).ToArray();
            int complexity = 1 + nodes.Count(n => n is IfStatementSyntax or ForStatementSyntax or ForEachStatementSyntax
                or WhileStatementSyntax or DoStatementSyntax or CatchClauseSyntax or ConditionalExpressionSyntax
                or CaseSwitchLabelSyntax or SwitchExpressionArmSyntax || n.IsKind(SyntaxKind.LogicalAndExpression)
                || n.IsKind(SyntaxKind.LogicalOrExpression) || n.IsKind(SyntaxKind.CoalesceExpression));
            int lines = function.DescendantTokens().Select(t => t.GetLocation().GetLineSpan().StartLinePosition.Line).Distinct().Count();
            var controls = nodes.Where(IsControl).ToArray();
            int depth = controls.Select(n => 1 + n.Ancestors().TakeWhile(p => p != function).Count(IsControl)).DefaultIfEmpty(0).Max();
            int bumps = controls.Count(n => !n.Ancestors().TakeWhile(p => p != function).Any(IsControl)
                && n.DescendantNodes(child => !IsFunction(child)).Any(IsControl));
            if (complexity >= 9) Add("CH01", Level(complexity, 15, 25), function, $"Complexity {complexity}");
            if (lines >= 50) Add("CH02", Level(lines, 80, 150), function, $"{lines} code lines");
            if (depth >= 4) Add("CH03", depth >= 5 ? "blocking" : "major", function, $"Control depth {depth}");
            if (bumps >= 2) Add("CH04", bumps >= 4 ? "blocking" : "major", function, $"{bumps} nested control groups");
            if (lines >= 60 && complexity >= 15 && depth >= 4) Add("CH08", "blocking", function, "Brain method");
            var parameters = Parameters(function);
            if (parameters.Count >= 5) Add("CH06", parameters.Count >= 7 ? "major" : "minor", function, $"{parameters.Count} parameters");
            if (function is ConstructorDeclarationSyntax && parameters.Count >= 5)
                Add("CH07", parameters.Count >= 8 ? "major" : "minor", function, $"{parameters.Count} constructor parameters");
            if (parameters.Count >= 4 && parameters.All(p => p.Type is PredefinedTypeSyntax))
                Add("CH13", "minor", function, "At least four primitive parameters");
        }
        foreach (var type in root.DescendantNodes().OfType<TypeDeclarationSyntax>().Where(t => t.ParameterList is not null))
        {
            int count = type.ParameterList!.Parameters.Count;
            if (count >= 5) Add("CH07", count >= 8 ? "major" : "minor", type, $"{count} primary constructor parameters");
        }
        foreach (var condition in root.DescendantNodes().Select(Condition).OfType<ExpressionSyntax>())
        {
            int count = condition.DescendantNodesAndSelf().Count(n => n.IsKind(SyntaxKind.LogicalAndExpression) || n.IsKind(SyntaxKind.LogicalOrExpression));
            if (count >= 2) Add("CH05", count >= 4 ? "major" : "minor", condition, $"{count} logical operators");
        }
        foreach (var method in root.DescendantNodes().OfType<MethodDeclarationSyntax>())
            if (method.Modifiers.Any(SyntaxKind.AsyncKeyword) && method.ReturnType.ToString() == "void") Add("NET01", "blocking", method, "async void");
        foreach (var member in root.DescendantNodes().OfType<MemberAccessExpressionSyntax>())
        {
            string name = member.Name.Identifier.ValueText;
            if (name == "Result" || name == "Wait" || name == "GetResult") Add("NET02", "blocking", member, "Potential synchronous wait");
            if (member.ToString() == "DateTime.Now") Add("NET09", "minor", member, "Server local time");
        }
        foreach (var creation in root.DescendantNodes().OfType<ObjectCreationExpressionSyntax>())
            if (creation.Type.ToString().Split('.').Last() == "HttpClient") Add("NET03", "blocking", creation, "Direct HttpClient allocation");
        foreach (var clause in root.DescendantNodes().OfType<CatchClauseSyntax>())
        {
            if (clause.Block.Statements.Count == 0) Add("NET04", "blocking", clause, "Empty catch");
            if (clause.Declaration?.Type.ToString() is "Exception" or "System.Exception" && !clause.Block.DescendantNodes().OfType<ThrowStatementSyntax>().Any())
                Add("NET11", "major", clause, "Broad catch without rethrow");
        }
        foreach (var statement in root.DescendantNodes().OfType<ThrowStatementSyntax>())
            if (statement.Expression is IdentifierNameSyntax) Add("NET05", "major", statement, "Throwing an identifier may reset the stack");
        foreach (var call in root.DescendantNodes().OfType<InvocationExpressionSyntax>())
        {
            string expression = call.Expression.ToString();
            if (expression.EndsWith("Thread.Sleep", StringComparison.Ordinal)) Add("NET06", "major", call, "Blocking sleep");
            if (expression.EndsWith("FromSqlRaw", StringComparison.Ordinal) && call.ArgumentList.Arguments.FirstOrDefault()?.Expression is InterpolatedStringExpressionSyntax)
                Add("NET07", "blocking", call, "Interpolated raw SQL");
            if (Regex.IsMatch(expression, @"\.Log(Trace|Debug|Information|Warning|Error|Critical)$")
                && call.ArgumentList.Arguments.Any(a => a.Expression is InterpolatedStringExpressionSyntax)) Add("NET10", "minor", call, "Interpolated logging");
            if (call.Expression is MemberAccessExpressionSyntax { Name.Identifier.ValueText: "Where", Expression: InvocationExpressionSyntax inner }
                && inner.Expression is MemberAccessExpressionSyntax { Name.Identifier.ValueText: "ToList" }) Add("NET12", "major", call, "Filter after materialization");
        }
        foreach (var literal in root.DescendantNodes().OfType<LiteralExpressionSyntax>().Where(n => n.IsKind(SyntaxKind.StringLiteralExpression)))
            if (Regex.IsMatch(literal.Token.ValueText, @"ecpk_(live|test)_[A-Za-z0-9]{16,}|(?i:Password=)[^;$\s]{4,}"))
                Add("NET08", "blocking", literal, "Potential embedded secret");
        // Compare six consecutive nonempty code lines, without trivia; one finding per occurrence.
        var tokensByLine = tokens.GroupBy(t => t.GetLocation().GetLineSpan().StartLinePosition.Line + 1)
            .Select(g => (Line: g.Key, Text: string.Join(" ", g.Select(t => t.Text)))).ToArray();
        for (int i = 0; i + 6 <= tokensByLine.Length; i++)
        {
            string block = string.Join("\n", tokensByLine.Skip(i).Take(6).Select(l => l.Text));
            if (block.Count(char.IsLetterOrDigit) < 60) continue;
            int line = tokensByLine[i].Line;
            if (duplicateBlocks.TryGetValue(block, out var other))
            {
                if (other.File == file && i < other.Index + 6) continue;
                // Reserve normalized code-line indices, not physical lines: blank lines
                // must not cause overlapping windows to be charged more than once.
                if (Enumerable.Range(i, 6).Any(n => claimedLines.TryGetValue((path, n), out var owner) && owner != block)
                    || Enumerable.Range(other.Index, 6).Any(n => claimedLines.TryGetValue((other.File.Path, n), out var owner) && owner != block)) continue;
                AddAt(file, "CH10", "major", line, $"Six repeated code lines; first at {other.File.Path}:{other.Line}");
                AddAt(other.File, "CH10", "major", other.Line, "Six repeated code lines");
                foreach (int n in Enumerable.Range(i, 6)) claimedLines[(path, n)] = block;
                foreach (int n in Enumerable.Range(other.Index, 6)) claimedLines[(other.File.Path, n)] = block;
            }
            else duplicateBlocks.Add(block, (file, i, line));
        }
    }
    return result;
}
static int Line(SyntaxNode node) => node.GetLocation().GetLineSpan().StartLinePosition.Line + 1;
static string Level(int count, int major, int blocking) => count >= blocking ? "blocking" : count >= major ? "major" : "minor";
static void AddAt(FileReport file, string rule, string severity, int line, string message)
{
    if (!file.Findings.Any(f => f.Rule == rule && f.Line == line)) file.Findings.Add(new(rule, severity, line, message));
}
static bool IsFunction(SyntaxNode n) => n is BaseMethodDeclarationSyntax or LocalFunctionStatementSyntax or AnonymousFunctionExpressionSyntax or AccessorDeclarationSyntax;
static bool IsControl(SyntaxNode n) => n is IfStatementSyntax or ForStatementSyntax or ForEachStatementSyntax or WhileStatementSyntax or DoStatementSyntax or SwitchStatementSyntax or TryStatementSyntax;
static SeparatedSyntaxList<ParameterSyntax> Parameters(SyntaxNode n) => n switch
{
    BaseMethodDeclarationSyntax m => m.ParameterList.Parameters,
    LocalFunctionStatementSyntax m => m.ParameterList.Parameters,
    ParenthesizedLambdaExpressionSyntax m => m.ParameterList.Parameters,
    SimpleLambdaExpressionSyntax m => SyntaxFactory.SingletonSeparatedList(m.Parameter),
    _ => default
};
static ExpressionSyntax? Condition(SyntaxNode n) => n switch
{
    IfStatementSyntax c => c.Condition, WhileStatementSyntax c => c.Condition,
    DoStatementSyntax c => c.Condition, ForStatementSyntax c => c.Condition,
    ConditionalExpressionSyntax c => c.Condition, _ => null
};
static string Markdown(List<FileReport> files, double score, bool gate, List<string> failures)
{
    var text = new StringBuilder("# Code Health pédagogique\n\nAnalyse syntaxique Roslyn des fichiers C# ; CH12, Razor et configuration exigent une revue humaine.\n\n| Fichier | Lignes | Score |\n|---|---:|---:|\n");
    foreach (var file in files)
    {
        text.AppendLine($"| {file.Path} | {file.Lines} | {file.Score.ToString("0.00", CultureInfo.InvariantCulture)} |");
        foreach (var finding in file.Findings.OrderBy(f => f.Line).ThenBy(f => f.Rule)) text.AppendLine($"\n- {file.Path}:{finding.Line} {finding.Rule} [{finding.Severity}] {finding.Message}");
    }
    text.AppendLine($"\nMoyenne pondérée : {score.ToString("0.00", CultureInfo.InvariantCulture)}. CH12 : à examiner manuellement.");
    if (gate) text.AppendLine(failures.Count == 0 ? "\nPORTE OK" : "\nPORTE FERMÉE\n" + string.Join("\n", failures.Select(f => "- " + f)));
    return text.ToString();
}
sealed record Finding(string Rule, string Severity, int Line, string Message);
sealed record FileReport(string Path, int Lines, List<Finding> Findings)
{
    public double Score => Math.Max(1, 10 - Findings.Sum(f => f.Severity switch { "blocking" => 2.0, "major" => 0.75, _ => 0.25 }));
}

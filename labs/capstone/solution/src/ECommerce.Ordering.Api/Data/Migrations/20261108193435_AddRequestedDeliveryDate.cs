using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ECommerce.Ordering.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddRequestedDeliveryDate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateOnly>(
                name: "RequestedDeliveryDate",
                table: "Orders",
                type: "date",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Orders_RequestedDeliveryDate",
                table: "Orders",
                column: "RequestedDeliveryDate");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Orders_RequestedDeliveryDate",
                table: "Orders");

            migrationBuilder.DropColumn(
                name: "RequestedDeliveryDate",
                table: "Orders");
        }
    }
}

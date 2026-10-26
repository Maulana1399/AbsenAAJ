<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_events', function (Blueprint $table) {
            $table->decimal('latitude', 10, 7)->nullable()->after('status');
            $table->decimal('longitude', 10, 7)->nullable()->after('latitude');
            $table->decimal('accuracy_meters', 10, 2)->nullable()->after('longitude');
            $table->decimal('distance_meters', 10, 2)->nullable()->after('accuracy_meters');
            $table->boolean('location_valid')->nullable()->after('distance_meters');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_events', function (Blueprint $table) {
            $table->dropColumn(['latitude', 'longitude', 'accuracy_meters', 'distance_meters', 'location_valid']);
        });
    }
};

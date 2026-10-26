<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attendance_photos', function (Blueprint $table) {
            $table->id();
            $table->foreignId('attendance_event_id')->constrained('attendance_events')->cascadeOnDelete();
            $table->string('storage_path');
            $table->string('original_filename')->nullable();
            $table->string('mime_type');
            $table->unsignedBigInteger('file_size');
            $table->string('sha256', 64);
            $table->timestamp('captured_at')->nullable();
            $table->timestamps();

            $table->unique('attendance_event_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendance_photos');
    }
};

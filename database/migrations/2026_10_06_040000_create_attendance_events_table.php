<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attendance_events', function (Blueprint $table) {
            $table->id();
            $table->string('client_event_id')->unique();
            $table->foreignId('employee_id')->constrained()->cascadeOnDelete();
            $table->foreignId('device_id')->constrained()->cascadeOnDelete();
            $table->string('event_type');
            $table->timestamp('event_at');
            $table->string('status');
            $table->string('sync_source')->default('mobile');
            $table->timestamp('server_received_at');
            $table->timestamps();

            $table->index(['employee_id', 'event_at']);
            $table->index(['employee_id', 'event_type']);
            $table->index('event_type');
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendance_events');
    }
};

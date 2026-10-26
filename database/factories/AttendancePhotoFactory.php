<?php

namespace Database\Factories;

use App\Models\AttendanceEvent;
use App\Models\AttendancePhoto;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<AttendancePhoto>
 */
class AttendancePhotoFactory extends Factory
{
    protected $model = AttendancePhoto::class;

    public function definition(): array
    {
        return [
            'attendance_event_id' => AttendanceEvent::factory(),
            'storage_path' => 'attendance/'.Str::uuid()->toString().'.jpg',
            'original_filename' => 'selfie.jpg',
            'mime_type' => 'image/jpeg',
            'file_size' => fake()->numberBetween(10000, 500000),
            'sha256' => str_repeat('a', 64),
            'captured_at' => now(),
        ];
    }
}

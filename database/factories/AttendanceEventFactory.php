<?php

namespace Database\Factories;

use App\Enums\AttendanceEventType;
use App\Enums\AttendanceStatus;
use App\Models\AttendanceEvent;
use App\Models\Device;
use App\Models\Employee;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * @extends Factory<AttendanceEvent>
 */
class AttendanceEventFactory extends Factory
{
    protected $model = AttendanceEvent::class;

    public function definition(): array
    {
        return [
            'client_event_id' => Str::uuid()->toString(),
            'employee_id' => Employee::factory(),
            'device_id' => Device::factory(),
            'event_type' => AttendanceEventType::CHECK_IN,
            'event_at' => Carbon::parse('08:00:00', 'Asia/Makassar'),
            'status' => AttendanceStatus::ON_TIME,
            'sync_source' => 'mobile',
            'server_received_at' => now(),
            'latitude' => -5.147700,
            'longitude' => 119.432600,
            'accuracy_meters' => 50,
            'distance_meters' => 0,
            'location_valid' => true,
        ];
    }
}

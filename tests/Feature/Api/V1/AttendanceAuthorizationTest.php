<?php

namespace Tests\Feature\Api\V1;

use App\Enums\AttendanceEventType;
use App\Models\AttendanceEvent;
use App\Models\Device;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceAuthorizationTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function seedEvent($employee, string $eventType, string $time): AttendanceEvent
    {
        return AttendanceEvent::query()->create([
            'client_event_id' => (string) Str::uuid(),
            'employee_id' => $employee->id,
            'device_id' => Device::factory()->create(['employee_id' => $employee->id])->id,
            'event_type' => $eventType,
            'event_at' => Carbon::parse("2026-10-06 {$time}:00", 'Asia/Makassar'),
            'status' => 'ON_TIME',
            'sync_source' => 'mobile',
            'server_received_at' => now(),
        ]);
    }

    public function test_employee_only_sees_own_attendance(): void
    {
        [$userA, $employeeA] = $this->makeEmployeeUser();
        [$userB, $employeeB] = $this->makeEmployeeUser();

        $eventA = $this->seedEvent($employeeA, AttendanceEventType::CHECK_IN->value, '08:00');
        $this->seedEvent($employeeB, AttendanceEventType::CHECK_IN->value, '08:10');

        $response = $this->getJson('/api/v1/attendance', $this->tokenHeader($userA));

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
        $this->assertSame($eventA->id, $response->json('data.0.id'));
        $this->assertSame($employeeA->id, $response->json('data.0.employee_id'));
    }

    public function test_history_can_be_filtered_by_date_range(): void
    {
        [$user, $employee] = $this->makeEmployeeUser();

        $inRange = $this->seedEvent($employee, AttendanceEventType::CHECK_IN->value, '08:00');
        $outside = AttendanceEvent::query()->create([
            'client_event_id' => (string) Str::uuid(),
            'employee_id' => $employee->id,
            'device_id' => Device::factory()->create(['employee_id' => $employee->id])->id,
            'event_type' => AttendanceEventType::CHECK_OUT->value,
            'event_at' => Carbon::parse('2026-11-01 17:00:00', 'Asia/Makassar'),
            'status' => 'NORMAL',
            'sync_source' => 'mobile',
            'server_received_at' => now(),
        ]);

        $response = $this->getJson('/api/v1/attendance?from=2026-10-01&to=2026-10-31', $this->tokenHeader($user));

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
        $this->assertSame($inRange->id, $response->json('data.0.id'));
        $this->assertNotSame($outside->id, $response->json('data.0.id'));
    }

    public function test_attendance_requires_authentication(): void
    {
        $this->getJson('/api/v1/attendance')->assertStatus(401);
    }

    public function test_user_without_employee_cannot_read_attendance(): void
    {
        $user = User::factory()->employee()->create();

        $response = $this->getJson('/api/v1/attendance', $this->tokenHeader($user));

        $response->assertStatus(403)->assertJson(['code' => 'EMPLOYEE_REQUIRED']);
    }
}

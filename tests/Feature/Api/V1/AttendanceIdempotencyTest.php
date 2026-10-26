<?php

namespace Tests\Feature\Api\V1;

use App\Models\AttendanceEvent;
use App\Models\Device;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceIdempotencyTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function postAs($user, string $deviceUuid, string $eventType, string $clientEventId, string $eventAt): TestResponse
    {
        return $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => $clientEventId,
            'device_uuid' => $deviceUuid,
            'event_type' => $eventType,
            'event_at' => $eventAt,
            'photo' => $this->photoUpload(),
        ], $this->gpsInside()), $this->tokenHeader($user));
    }

    public function test_replayed_idempotent_event_returns_existing_record(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');
        $id = (string) Str::uuid();

        $first = $this->postAs($user, 'device-0001', 'CHECK_IN', $id, $this->eventAt('08:00'));
        $second = $this->postAs($user, 'device-0001', 'CHECK_IN', $id, $this->eventAt('08:00'));

        $this->assertDatabaseCount('attendance_events', 1);
        $this->assertSame($first->json('data.id'), $second->json('data.id'));
    }

    public function test_unique_constraint_blocks_duplicate_inserts(): void
    {
        [$user, $employee] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');
        $id = (string) Str::uuid();

        AttendanceEvent::query()->create([
            'client_event_id' => $id,
            'employee_id' => $employee->id,
            'device_id' => Device::first()->id,
            'event_type' => 'CHECK_IN',
            'event_at' => now(),
            'status' => 'ON_TIME',
            'sync_source' => 'mobile',
            'server_received_at' => now(),
        ]);

        $replay = $this->postAs($user, 'device-0001', 'CHECK_IN', $id, $this->eventAt('08:00'));

        $replay->assertOk();
        $this->assertDatabaseCount('attendance_events', 1);
    }

    public function test_same_client_event_id_by_different_employee_is_rejected(): void
    {
        [$userA] = $this->makeEmployeeUser();
        [$userB] = $this->makeEmployeeUser();

        $this->registerDeviceVia($userA, 'device-a');
        $this->registerDeviceVia($userB, 'device-b');

        $id = (string) Str::uuid();

        $this->postAs($userA, 'device-a', 'CHECK_IN', $id, $this->eventAt('08:00'))->assertCreated();

        $response = $this->postAs($userB, 'device-b', 'CHECK_IN', $id, $this->eventAt('08:00'));

        $response->assertStatus(409)
            ->assertJson([
                'message' => 'client_event_id sudah digunakan oleh event lain.',
                'code' => 'ATTENDANCE_EVENT_CONFLICT',
            ]);

        $this->assertDatabaseCount('attendance_events', 1);
    }
}

<?php

namespace Tests\Feature\Api\V1;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceCheckInTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    public function test_check_in_succeeds(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->travelToAttendanceTime('08:00');

        $response = $this->postEventVia($user, 'device-0001');

        $response->assertCreated()
            ->assertJsonStructure([
                'data' => [
                    'id', 'client_event_id', 'event_type', 'status', 'event_at', 'server_received_at',
                ],
            ])
            ->assertJsonPath('data.event_type', 'CHECK_IN')
            ->assertJsonPath('data.status', 'ON_TIME');

        $this->assertDatabaseCount('attendance_events', 1);
    }

    public function test_check_in_at_0829_is_on_time(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->travelToAttendanceTime('08:29');

        $response = $this->postEventVia($user, 'device-0001', [], [
            'event_at' => $this->eventAt('08:29'),
        ]);

        $response->assertCreated()->assertJsonPath('data.status', 'ON_TIME');
    }

    public function test_check_in_at_0830_is_on_time(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->travelToAttendanceTime('08:30');

        $response = $this->postEventVia($user, 'device-0001', [], [
            'event_at' => $this->eventAt('08:30'),
        ]);

        $response->assertCreated()->assertJsonPath('data.status', 'ON_TIME');
    }

    public function test_check_in_at_0835_is_on_time(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->travelToAttendanceTime('08:35');

        $response = $this->postEventVia($user, 'device-0001', [], [
            'event_at' => $this->eventAt('08:35'),
        ]);

        $response->assertCreated()->assertJsonPath('data.status', 'ON_TIME');
    }

    public function test_check_in_at_0836_is_late(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->travelToAttendanceTime('08:36');

        $response = $this->postEventVia($user, 'device-0001', [], [
            'event_at' => $this->eventAt('08:36'),
        ]);

        $response->assertCreated()->assertJsonPath('data.status', 'LATE');
    }

    public function test_check_in_requires_active_registered_device(): void
    {
        [$user] = $this->makeEmployeeUser();

        $response = $this->postEventVia($user, 'unregistered-device');

        $response->assertStatus(404)
            ->assertJson(['code' => 'DEVICE_NOT_FOUND']);
    }

    public function test_second_employee_cannot_use_first_employees_device(): void
    {
        [$userA] = $this->makeEmployeeUser();
        [$userB] = $this->makeEmployeeUser();
        $this->registerDeviceVia($userA, 'device-0001')->assertOk();

        $response = $this->postEventVia($userB, 'device-0001');

        $response->assertStatus(404)
            ->assertJson(['code' => 'DEVICE_NOT_FOUND']);

        $this->assertDatabaseCount('attendance_events', 0);
    }

    public function test_double_check_in_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');
        $this->postEventVia($user, 'device-0001')->assertCreated();

        $response = $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:40'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside()), $this->tokenHeader($user));

        $response->assertStatus(422)
            ->assertJson([
                'message' => 'Employee sudah melakukan check-in.',
                'code' => 'ALREADY_CHECKED_IN',
            ]);

        $this->assertDatabaseCount('attendance_events', 1);
    }

    public function test_duplicate_client_event_id_does_not_create_duplicate(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $clientEventId = (string) Str::uuid();

        $payload = array_merge([
            'client_event_id' => $clientEventId,
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside());

        $first = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));
        $first->assertCreated();

        $second = $this->post('/api/v1/attendance/events', $payload, $this->tokenHeader($user));
        $second->assertOk();

        $this->assertDatabaseCount('attendance_events', 1);
        $this->assertDatabaseCount('attendance_photos', 1);
        $this->assertSame(
            $first->json('data.id'),
            $second->json('data.id'),
        );
    }

    public function test_check_in_by_user_without_employee_is_rejected(): void
    {
        $user = User::factory()->employee()->create();

        $response = $this->postEventVia($user, 'device-0001');

        $response->assertStatus(403)
            ->assertJson(['code' => 'EMPLOYEE_REQUIRED']);
    }
}

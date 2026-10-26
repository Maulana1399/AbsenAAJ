<?php

namespace Tests\Feature\Api\V1;

use App\Enums\AttendanceEventType;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceCheckOutTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function checkIn($user, string $deviceUuid = 'device-0001'): void
    {
        $this->registerDeviceVia($user, $deviceUuid)->assertOk();

        $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => $deviceUuid,
            'event_type' => AttendanceEventType::CHECK_IN->value,
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside()), $this->tokenHeader($user))->assertCreated();
    }

    private function checkOutAt($user, string $time, string $deviceUuid = 'device-0001'): TestResponse
    {
        return $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => $deviceUuid,
            'event_type' => AttendanceEventType::CHECK_OUT->value,
            'event_at' => $this->eventAt($time),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside()), $this->tokenHeader($user));
    }

    public function test_check_out_after_check_in_succeeds(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->checkIn($user);

        $response = $this->checkOutAt($user, '17:00');

        $response->assertCreated()
            ->assertJsonPath('data.event_type', 'CHECK_OUT')
            ->assertJsonPath('data.status', 'NORMAL');

        $this->assertDatabaseCount('attendance_events', 2);
    }

    public function test_check_out_at_1659_is_early_checkout(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->checkIn($user);

        $response = $this->checkOutAt($user, '16:59');

        $response->assertCreated()->assertJsonPath('data.status', 'EARLY_CHECKOUT');
    }

    public function test_check_out_at_1700_is_normal(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->checkIn($user);

        $response = $this->checkOutAt($user, '17:00');

        $response->assertCreated()->assertJsonPath('data.status', 'NORMAL');
    }

    public function test_check_out_at_1705_is_normal(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->checkIn($user);

        $response = $this->checkOutAt($user, '17:05');

        $response->assertCreated()->assertJsonPath('data.status', 'NORMAL');
    }

    public function test_check_out_before_check_in_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();

        $response = $this->checkOutAt($user, '17:00');

        $response->assertStatus(422)
            ->assertJson([
                'message' => 'Check-out membutuhkan check-in terlebih dahulu.',
                'code' => 'CHECK_IN_REQUIRED',
            ]);

        $this->assertDatabaseCount('attendance_events', 0);
    }

    public function test_double_check_out_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->checkIn($user);
        $this->checkOutAt($user, '17:00')->assertCreated();

        $response = $this->checkOutAt($user, '17:05');

        $response->assertStatus(422)
            ->assertJson([
                'message' => 'Employee sudah melakukan check-out.',
                'code' => 'ALREADY_CHECKED_OUT',
            ]);

        $this->assertDatabaseCount('attendance_events', 2);
    }

    public function test_check_out_after_late_check_in_works(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001')->assertOk();

        $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => AttendanceEventType::CHECK_IN->value,
            'event_at' => $this->eventAt('09:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside()), $this->tokenHeader($user))->assertJsonPath('data.status', 'LATE');

        $response = $this->checkOutAt($user, '17:00');

        $response->assertCreated()->assertJsonPath('data.status', 'NORMAL');
    }
}

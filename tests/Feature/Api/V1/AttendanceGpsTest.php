<?php

namespace Tests\Feature\Api\V1;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceGpsTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function postWithGps($user, array $gps): TestResponse
    {
        return $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $gps), $this->tokenHeader($user));
    }

    public function test_latitude_is_required(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $gps = $this->gpsInside();
        unset($gps['latitude']);

        $this->postWithGps($user, $gps)->assertStatus(422)->assertJsonValidationErrors('latitude');
    }

    public function test_longitude_is_required(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $gps = $this->gpsInside();
        unset($gps['longitude']);

        $this->postWithGps($user, $gps)->assertStatus(422)->assertJsonValidationErrors('longitude');
    }

    public function test_accuracy_is_required(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $gps = $this->gpsInside();
        unset($gps['accuracy_meters']);

        $this->postWithGps($user, $gps)->assertStatus(422)->assertJsonValidationErrors('accuracy_meters');
    }

    public function test_invalid_latitude_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->postWithGps($user, ['latitude' => 91, 'longitude' => 119.4, 'accuracy_meters' => 50])
            ->assertStatus(422)->assertJsonValidationErrors('latitude');

        $this->postWithGps($user, ['latitude' => -91, 'longitude' => 119.4, 'accuracy_meters' => 50])
            ->assertStatus(422)->assertJsonValidationErrors('latitude');
    }

    public function test_invalid_longitude_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->postWithGps($user, ['latitude' => -5.1, 'longitude' => 181, 'accuracy_meters' => 50])
            ->assertStatus(422)->assertJsonValidationErrors('longitude');

        $this->postWithGps($user, ['latitude' => -5.1, 'longitude' => -181, 'accuracy_meters' => 50])
            ->assertStatus(422)->assertJsonValidationErrors('longitude');
    }

    public function test_negative_accuracy_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $this->postWithGps($user, ['latitude' => -5.1, 'longitude' => 119.4, 'accuracy_meters' => -1])
            ->assertStatus(422)->assertJsonValidationErrors('accuracy_meters');
    }

    public function test_low_accuracy_is_rejected_with_location_low_accuracy(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postWithGps($user, $this->gpsInside(accuracy: 150));

        $response->assertStatus(422)
            ->assertJson([
                'code' => 'LOCATION_LOW_ACCURACY',
            ]);

        $this->assertDatabaseCount('attendance_events', 0);
    }

    public function test_low_accuracy_is_not_treated_as_outside_geofence(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postWithGps($user, $this->gpsInside(accuracy: 101));

        $response->assertJsonPath('code', 'LOCATION_LOW_ACCURACY');
        $this->assertNotSame('OUTSIDE_GEOFENCE', $response->json('code'));
    }

    public function test_accuracy_at_limit_is_accepted(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postWithGps($user, $this->gpsInside(accuracy: 100));

        $response->assertCreated();
    }

    public function test_client_cannot_override_distance_or_location_validity(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->post('/api/v1/attendance/events', array_merge(
            $this->postEventDefaults(),
            ['distance_meters' => 999999, 'location_valid' => false],
        ), $this->tokenHeader($user));

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['distance_meters', 'location_valid']);
    }

    public function test_client_cannot_override_status_employee_or_branch(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->post('/api/v1/attendance/events', array_merge(
            $this->postEventDefaults(),
            ['status' => 'LATE', 'employee_id' => 1, 'branch_id' => 1, 'sync_source' => 'fake'],
        ), $this->tokenHeader($user));

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['status', 'employee_id', 'branch_id', 'sync_source']);
    }

    private function postEventDefaults(): array
    {
        return array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $this->gpsInside());
    }
}

<?php

namespace Tests\Feature\Api\V1;

use App\Models\Branch;
use App\Models\Employee;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class AttendanceGeofenceTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function postEvent($user, array $gps): TestResponse
    {
        return $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => 'device-0001',
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'photo' => $this->photoUpload(),
        ], $gps), $this->tokenHeader($user));
    }

    public function test_coordinate_inside_radius_is_accepted(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postEvent($user, $this->gpsInside());

        $response->assertCreated()
            ->assertJsonPath('data.location_valid', true)
            ->assertJsonPath('data.distance_meters', '0.00')
            ->assertJsonPath('data.latitude', '-5.1477000');
    }

    public function test_coordinate_near_branch_has_server_computed_distance(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postEvent($user, $this->gpsNearBoundary());

        $response->assertCreated()
            ->assertJsonPath('data.location_valid', true);

        $distance = (float) $response->json('data.distance_meters');
        $this->assertGreaterThan(900, $distance);
        $this->assertLessThan($this->branchRadiusMeters, $distance);
    }

    public function test_coordinate_at_boundary_is_accepted(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postEvent($user, $this->gpsNearBoundary());

        $response->assertCreated()
            ->assertJsonPath('data.location_valid', true);
    }

    public function test_coordinate_outside_radius_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postEvent($user, $this->gpsOutside());

        $response->assertStatus(422)
            ->assertJson([
                'code' => 'OUTSIDE_GEOFENCE',
            ]);

        $this->assertDatabaseCount('attendance_events', 0);
        $this->assertDatabaseCount('attendance_photos', 0);
    }

    public function test_employee_without_branch_is_rejected(): void
    {
        $user = User::factory()->employee()->create();
        Employee::factory()->create(['user_id' => $user->id, 'branch_id' => null]);

        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->postEvent($user, $this->gpsInside());

        $response->assertStatus(422)
            ->assertJson([
                'code' => 'BRANCH_NOT_CONFIGURED',
            ]);
    }

    public function test_branch_without_coordinates_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $user->employee->update([
            'branch_id' => Branch::factory()->create([
                'latitude' => null,
                'longitude' => null,
                'radius_meters' => 1000,
            ])->id,
        ]);

        $response = $this->postEvent($user, $this->gpsInside());

        $response->assertStatus(422)
            ->assertJson([
                'code' => 'BRANCH_LOCATION_NOT_CONFIGURED',
            ]);
    }

    public function test_branch_without_radius_is_rejected(): void
    {
        [$user] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $user->employee->update([
            'branch_id' => Branch::factory()->create([
                'latitude' => $this->branchLatitude,
                'longitude' => $this->branchLongitude,
                'radius_meters' => null,
            ])->id,
        ]);

        $response = $this->postEvent($user, $this->gpsInside());

        $response->assertStatus(422)
            ->assertJson([
                'code' => 'BRANCH_LOCATION_NOT_CONFIGURED',
            ]);
    }
}

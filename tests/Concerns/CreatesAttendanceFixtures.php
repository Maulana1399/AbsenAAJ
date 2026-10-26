<?php

namespace Tests\Concerns;

use App\Models\Branch;
use App\Models\Employee;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

trait CreatesAttendanceFixtures
{
    protected float $branchLatitude = -5.1477;

    protected float $branchLongitude = 119.4326;

    protected int $branchRadiusMeters = 1000;

    protected function makeEmployeeUser(array $userOverrides = [], array $employeeOverrides = []): array
    {
        $user = User::factory()->employee()->create($userOverrides);

        $branch = $this->makeConfiguredBranch();

        $employee = Employee::factory()->create(array_merge([
            'user_id' => $user->id,
            'branch_id' => $branch->id,
        ], $employeeOverrides));

        return [$user, $employee, $branch];
    }

    protected function makeConfiguredBranch(): Branch
    {
        return Branch::factory()->create([
            'latitude' => $this->branchLatitude,
            'longitude' => $this->branchLongitude,
            'radius_meters' => $this->branchRadiusMeters,
            'is_active' => true,
        ]);
    }

    protected function gpsInside(float $accuracy = 50): array
    {
        return [
            'latitude' => $this->branchLatitude,
            'longitude' => $this->branchLongitude,
            'accuracy_meters' => $accuracy,
        ];
    }

    protected function gpsOutside(float $accuracy = 50): array
    {
        return [
            'latitude' => $this->branchLatitude,
            'longitude' => $this->branchLongitude + 0.03,
            'accuracy_meters' => $accuracy,
        ];
    }

    protected function gpsNearBoundary(float $accuracy = 50): array
    {
        $degree = $this->branchRadiusMeters / 111320.0;

        return [
            'latitude' => $this->branchLatitude + ($degree * 0.999),
            'longitude' => $this->branchLongitude,
            'accuracy_meters' => $accuracy,
        ];
    }

    protected function photoUpload(string $name = 'selfie.jpg'): UploadedFile
    {
        return UploadedFile::fake()->image($name, 10, 10);
    }

    protected function tokenHeader(User $user): array
    {
        return ['Authorization' => 'Bearer '.$user->createToken('aaj-mobile')->plainTextToken];
    }

    protected function registerDeviceVia(User $user, string $deviceUuid, array $overrides = []): TestResponse
    {
        return $this->postJson('/api/v1/devices/register', array_merge([
            'device_uuid' => $deviceUuid,
            'platform' => 'android',
            'manufacturer' => 'Samsung',
            'model' => 'A15',
            'app_version' => '1.0.0',
        ], $overrides), $this->tokenHeader($user));
    }

    protected function postEventVia(User $user, string $deviceUuid, array $overrides = [], array $base = []): TestResponse
    {
        return $this->post('/api/v1/attendance/events', array_merge([
            'client_event_id' => (string) Str::uuid(),
            'device_uuid' => $deviceUuid,
            'event_type' => 'CHECK_IN',
            'event_at' => $this->eventAt('08:00'),
            'latitude' => $this->branchLatitude,
            'longitude' => $this->branchLongitude,
            'accuracy_meters' => 50,
            'photo' => $this->photoUpload(),
        ], $base, $overrides), $this->tokenHeader($user));
    }

    protected function eventAt(string $time): string
    {
        return Carbon::parse("2026-10-06 {$time}:00", 'Asia/Makassar')->toIso8601String();
    }

    /**
     * Laravel reuses the app container between requests within one test, and
     * Sanctum caches the resolved user on its guard instance. Reset the
     * guards after every HTTP call so the user does not leak between
     * consecutive requests (real HTTP is unaffected).
     */
    public function call($method, $uri, $parameters = [], $cookies = [], $files = [], $server = [], $content = null)
    {
        $response = parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);

        $this->app->make('auth')->forgetGuards();

        return $response;
    }
}

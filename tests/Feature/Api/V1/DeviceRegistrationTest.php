<?php

namespace Tests\Feature\Api\V1;

use App\Enums\DeviceStatus;
use App\Models\Device;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class DeviceRegistrationTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    public function test_employee_can_register_device(): void
    {
        [$user, $employee] = $this->makeEmployeeUser();

        $response = $this->registerDeviceVia($user, 'device-0001');

        $response->assertOk()
            ->assertJsonStructure([
                'data' => ['device' => [
                    'id', 'device_uuid', 'platform', 'status', 'registered_at', 'last_seen_at',
                ]],
            ])
            ->assertJsonPath('data.device.device_uuid', 'device-0001')
            ->assertJsonPath('data.device.status', 'ACTIVE');

        $this->assertDatabaseHas('devices', [
            'employee_id' => $employee->id,
            'device_uuid' => 'device-0001',
            'status' => 'ACTIVE',
        ]);
    }

    public function test_re_registering_same_device_does_not_create_duplicate(): void
    {
        [$user, $employee] = $this->makeEmployeeUser();
        $this->registerDeviceVia($user, 'device-0001');

        $response = $this->registerDeviceVia($user, 'device-0001', [
            'model' => 'A55',
            'app_version' => '1.1.0',
        ]);

        $response->assertOk();
        $this->assertDatabaseCount('devices', 1);
        $this->assertDatabaseHas('devices', [
            'employee_id' => $employee->id,
            'device_uuid' => 'device-0001',
            'model' => 'A55',
            'app_version' => '1.1.0',
        ]);
    }

    public function test_employee_can_register_multiple_devices(): void
    {
        [$user] = $this->makeEmployeeUser();

        $this->registerDeviceVia($user, 'device-0001')->assertOk();
        $this->registerDeviceVia($user, 'device-0002')->assertOk();

        $this->assertDatabaseCount('devices', 2);
    }

    public function test_device_uuid_owned_by_another_employee_is_rejected(): void
    {
        [$userA] = $this->makeEmployeeUser();
        [$userB] = $this->makeEmployeeUser();
        $this->registerDeviceVia($userA, 'device-0001')->assertOk();

        $response = $this->registerDeviceVia($userB, 'device-0001');

        $response->assertStatus(409)
            ->assertJson([
                'message' => 'Device sudah terdaftar untuk karyawan lain.',
                'code' => 'DEVICE_ALREADY_REGISTERED',
            ]);
    }

    public function test_user_without_employee_cannot_register_device(): void
    {
        $user = User::factory()->employee()->create();

        $response = $this->registerDeviceVia($user, 'device-0001');

        $response->assertStatus(403)
            ->assertJson(['code' => 'EMPLOYEE_REQUIRED']);
    }

    public function test_revoked_device_cannot_be_registered_again(): void
    {
        [$user, $employee] = $this->makeEmployeeUser();

        Device::query()->create([
            'employee_id' => $employee->id,
            'device_uuid' => 'device-revoked',
            'platform' => 'android',
            'status' => DeviceStatus::REVOKED,
        ]);

        $response = $this->registerDeviceVia($user, 'device-revoked');

        $response->assertStatus(403)
            ->assertJson([
                'message' => 'Device telah direvoke dan tidak dapat didaftarkan ulang.',
                'code' => 'DEVICE_REVOKED',
            ]);

        $this->assertDatabaseHas('devices', [
            'device_uuid' => 'device-revoked',
            'status' => 'REVOKED',
        ]);
    }

    public function test_revoked_device_cannot_be_used_for_attendance(): void
    {
        [$user, $employee] = $this->makeEmployeeUser();

        Device::query()->create([
            'employee_id' => $employee->id,
            'device_uuid' => 'device-revoked',
            'platform' => 'android',
            'status' => DeviceStatus::REVOKED,
        ]);

        $response = $this->postEventVia($user, 'device-revoked');

        $response->assertStatus(403)
            ->assertJson(['code' => 'DEVICE_REVOKED']);
    }
}

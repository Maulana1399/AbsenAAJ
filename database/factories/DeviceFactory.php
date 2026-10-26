<?php

namespace Database\Factories;

use App\Models\Device;
use App\Models\Employee;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<Device>
 */
class DeviceFactory extends Factory
{
    protected $model = Device::class;

    public function definition(): array
    {
        return [
            'employee_id' => Employee::factory(),
            'device_uuid' => Str::uuid()->toString(),
            'platform' => fake()->randomElement(['android', 'ios']),
            'manufacturer' => fake()->randomElement(['Samsung', 'Xiaomi', 'Apple', null]),
            'model' => fake()->word(),
            'app_version' => '1.0.0',
            'registered_at' => now(),
            'last_seen_at' => now(),
        ];
    }
}

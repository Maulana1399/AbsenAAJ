<?php

namespace Database\Factories;

use App\Enums\EmployeeStatus;
use App\Models\Branch;
use App\Models\Employee;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Employee>
 */
class EmployeeFactory extends Factory
{
    protected $model = Employee::class;

    public function definition(): array
    {
        return [
            'employee_number' => fake()->unique()->numerify('EMP-####'),
            'name' => fake()->name(),
            'phone' => fake()->phoneNumber(),
            'branch_id' => Branch::factory(),
            'user_id' => null,
            'status' => EmployeeStatus::ACTIVE,
            'joined_at' => now()->subMonths(6)->toDateString(),
        ];
    }

    public function forUser(User $user): static
    {
        return $this->state(fn () => [
            'user_id' => $user->id,
        ]);
    }
}

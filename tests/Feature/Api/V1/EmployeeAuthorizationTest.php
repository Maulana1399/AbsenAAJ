<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Employee;
use App\Models\User;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class EmployeeAuthorizationTest extends TestCase
{
    use RefreshDatabase;

    public function test_roles_can_be_distinguished(): void
    {
        $admin = User::factory()->admin()->create();
        $hr = User::factory()->hr()->create();
        $employee = User::factory()->employee()->create();

        $this->assertSame(UserRole::ADMIN, $admin->role);
        $this->assertSame(UserRole::HR, $hr->role);
        $this->assertSame(UserRole::EMPLOYEE, $employee->role);
        $this->assertNotSame($admin->role, $hr->role);
    }

    public function test_hr_can_create_employee(): void
    {
        $hr = User::factory()->hr()->create();

        $this->actingAs($hr);

        Employee::create([
            'employee_number' => 'EMP-0001',
            'name' => 'Budi',
        ]);

        $this->assertTrue($hr->can('create', Employee::class));
        $this->assertDatabaseHas('employees', ['employee_number' => 'EMP-0001']);
    }

    public function test_hr_can_update_employee(): void
    {
        $hr = User::factory()->hr()->create();
        $employee = Employee::factory()->create(['name' => 'Budi']);

        $this->actingAs($hr)->assertTrue($hr->can('update', $employee));

        $employee->update(['name' => 'Budi Updated']);

        $this->assertDatabaseHas('employees', ['name' => 'Budi Updated']);
    }

    public function test_hr_cannot_delete_employee(): void
    {
        $hr = User::factory()->hr()->create();
        $employee = Employee::factory()->create();

        $this->actingAs($hr)->assertFalse($hr->can('delete', $employee));

        $this->assertDatabaseHas('employees', ['id' => $employee->id]);
    }

    public function test_admin_can_delete_employee(): void
    {
        $admin = User::factory()->admin()->create();
        $employee = Employee::factory()->create();

        $this->actingAs($admin)->assertTrue($admin->can('delete', $employee));

        $employee->delete();

        $this->assertSoftDeleted('employees', ['id' => $employee->id]);
    }

    public function test_employee_role_cannot_manage_employees(): void
    {
        $employee = User::factory()->employee()->create();
        $target = Employee::factory()->create();

        $this->actingAs($employee);

        $this->assertFalse($employee->can('create', Employee::class));
        $this->assertFalse($employee->can('update', $target));
        $this->assertFalse($employee->can('delete', $target));
    }

    public function test_force_delete_is_never_allowed(): void
    {
        $admin = User::factory()->admin()->create();
        $employee = Employee::factory()->create();

        $this->actingAs($admin)->assertFalse($admin->can('forceDelete', $employee));
    }

    public function test_filament_panel_access_by_role(): void
    {
        $admin = User::factory()->admin()->create();
        $hr = User::factory()->hr()->create();
        $employee = User::factory()->employee()->create();

        $panel = Filament::getDefaultPanel();

        $this->assertTrue($admin->canAccessPanel($panel));
        $this->assertTrue($hr->canAccessPanel($panel));
        $this->assertFalse($employee->canAccessPanel($panel));
    }
}

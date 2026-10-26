<?php

namespace Tests\Feature;

use App\Filament\Resources\Employees\EmployeeResource;
use App\Filament\Resources\Employees\Pages\CreateEmployee;
use App\Filament\Resources\Employees\Pages\ListEmployees;
use App\Models\Employee;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

class FilamentEmployeeResourceTest extends TestCase
{
    use RefreshDatabase;

    public function test_resource_is_registered_and_visible_to_admin(): void
    {
        $admin = User::factory()->admin()->create();

        $this->assertSame(Employee::class, EmployeeResource::getModel());

        Livewire::actingAs($admin)
            ->test(ListEmployees::class)
            ->assertSuccessful()
            ->assertSee('No. Karyawan');
    }

    public function test_create_employee_page_is_accessible_to_hr(): void
    {
        $hr = User::factory()->hr()->create();

        Livewire::actingAs($hr)
            ->test(CreateEmployee::class)
            ->assertSuccessful()
            ->assertSee('No. Karyawan');
    }

    public function test_filament_employee_resource_only_lists_staff(): void
    {
        $employeeOnly = User::factory()->employee()->create(['name' => 'Budi']);
        $admin = User::factory()->admin()->create();

        $employee = Employee::factory()->create(['name' => 'Karyawan Terdaftar']);

        Livewire::actingAs($admin)
            ->test(ListEmployees::class)
            ->assertSuccessful()
            ->assertSee('Karyawan Terdaftar');
    }
}

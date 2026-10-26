<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\User;
use Filament\Auth\Pages\Login;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

class FilamentAccessTest extends TestCase
{
    use RefreshDatabase;

    public function test_active_admin_can_access_panel(): void
    {
        $admin = User::factory()->admin()->create();

        $this->actingAs($admin)
            ->get('/admin')
            ->assertSuccessful();
    }

    public function test_active_hr_can_access_panel(): void
    {
        $hr = User::factory()->hr()->create();

        $this->actingAs($hr)
            ->get('/admin')
            ->assertSuccessful();
    }

    public function test_active_employee_cannot_access_panel(): void
    {
        $employee = User::factory()->employee()->create();

        $this->actingAs($employee)
            ->get('/admin')
            ->assertForbidden();
    }

    public function test_inactive_admin_and_hr_cannot_access_panel(): void
    {
        $inactiveAdmin = User::factory()->admin()->create(['is_active' => false]);
        $inactiveHr = User::factory()->hr()->create(['is_active' => false]);

        foreach ([$inactiveAdmin, $inactiveHr] as $user) {
            $this->actingAs($user)
                ->get('/admin')
                ->assertForbidden();
        }
    }

    public function test_can_access_panel_requires_active_status_and_admin_or_hr_role(): void
    {
        $panel = Filament::getPanel('admin');

        $cases = [
            [UserRole::ADMIN, true, true],
            [UserRole::HR, true, true],
            [UserRole::EMPLOYEE, true, false],
            [UserRole::ADMIN, false, false],
            [UserRole::HR, false, false],
            [UserRole::EMPLOYEE, false, false],
        ];

        foreach ($cases as [$role, $isActive, $expected]) {
            $user = User::factory()->create([
                'role' => $role,
                'is_active' => $isActive,
            ]);

            $this->assertSame($expected, $user->canAccessPanel($panel));
        }
    }

    public function test_inactive_user_cannot_log_in_to_filament_panel(): void
    {
        User::factory()->admin()->create([
            'email' => 'inactive-admin@example.com',
            'password' => 'password',
            'is_active' => false,
        ]);

        Filament::setCurrentPanel(Filament::getPanel('admin'));

        Livewire::test(Login::class)
            ->set('data.email', 'inactive-admin@example.com')
            ->set('data.password', 'password')
            ->call('authenticate')
            ->assertHasErrors(['data.email']);

        $this->assertGuest();
    }

    public function test_active_admin_can_log_in_to_filament_panel(): void
    {
        $admin = User::factory()->admin()->create([
            'email' => 'active-admin@example.com',
            'password' => 'password',
        ]);

        Filament::setCurrentPanel(Filament::getPanel('admin'));

        Livewire::test(Login::class)
            ->set('data.email', 'active-admin@example.com')
            ->set('data.password', 'password')
            ->call('authenticate')
            ->assertHasNoErrors();

        $this->assertAuthenticatedAs($admin);
    }
}

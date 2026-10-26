<?php

namespace Tests\Feature;

use App\Filament\Resources\Branches\BranchResource;
use App\Filament\Resources\Branches\Pages\CreateBranch;
use App\Filament\Resources\Branches\Pages\EditBranch;
use App\Filament\Resources\Branches\Pages\ListBranches;
use App\Filament\Resources\Employees\Pages\CreateEmployee;
use App\Models\Branch;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

class FilamentBranchResourceTest extends TestCase
{
    use RefreshDatabase;

    public function test_resource_is_registered_and_visible_to_admin(): void
    {
        $admin = User::factory()->admin()->create();
        $branch = Branch::factory()->create(['name' => 'Cabang Utama']);

        $this->assertSame(Branch::class, BranchResource::getModel());

        Livewire::actingAs($admin)
            ->test(ListBranches::class)
            ->assertSuccessful()
            ->assertSee('Cabang Utama')
            ->assertSee($branch->code);
    }

    public function test_hr_can_create_a_branch(): void
    {
        $hr = User::factory()->hr()->create();

        Livewire::actingAs($hr)
            ->test(CreateBranch::class)
            ->set('data.code', 'BR-TEST')
            ->set('data.name', 'Cabang Baru')
            ->set('data.latitude', -5.147665)
            ->set('data.longitude', 119.432732)
            ->set('data.radius_meters', 150)
            ->set('data.timezone', 'Asia/Makassar')
            ->set('data.is_active', true)
            ->call('create')
            ->assertHasNoFormErrors();

        $this->assertDatabaseHas('branches', [
            'code' => 'BR-TEST',
            'name' => 'Cabang Baru',
            'is_active' => true,
        ]);
    }

    public function test_admin_can_update_a_branch(): void
    {
        $admin = User::factory()->admin()->create();
        $branch = Branch::factory()->create(['name' => 'Nama Lama']);

        Livewire::actingAs($admin)
            ->test(EditBranch::class, ['record' => $branch->getRouteKey()])
            ->set('data.name', 'Nama Baru')
            ->call('save')
            ->assertHasNoFormErrors();

        $this->assertSame('Nama Baru', $branch->fresh()->name);
    }

    public function test_employee_cannot_manage_branches(): void
    {
        $employee = User::factory()->employee()->create();
        $branch = Branch::factory()->create();

        $this->actingAs($employee);

        $this->assertFalse($employee->can('viewAny', Branch::class));
        $this->assertFalse($employee->can('view', $branch));
        $this->assertFalse($employee->can('create', Branch::class));
        $this->assertFalse($employee->can('update', $branch));
        $this->assertFalse($employee->can('delete', $branch));
    }

    public function test_employee_form_only_offers_active_branches(): void
    {
        $admin = User::factory()->admin()->create();
        Branch::factory()->create(['name' => 'Cabang Aktif', 'is_active' => true]);
        Branch::factory()->create(['name' => 'Cabang Nonaktif', 'is_active' => false]);

        Livewire::actingAs($admin)
            ->test(CreateEmployee::class)
            ->assertSuccessful()
            ->assertSee('Cabang Aktif')
            ->assertDontSee('Cabang Nonaktif');
    }
}

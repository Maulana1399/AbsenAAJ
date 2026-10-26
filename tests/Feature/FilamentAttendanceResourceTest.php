<?php

namespace Tests\Feature;

use App\Filament\Resources\AttendanceEvents\AttendanceEventResource;
use App\Filament\Resources\AttendanceEvents\Pages\ListAttendanceEvents;
use App\Models\AttendanceEvent;
use App\Models\Device;
use App\Models\Employee;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\CreatesAttendanceFixtures;
use Tests\TestCase;

class FilamentAttendanceResourceTest extends TestCase
{
    use CreatesAttendanceFixtures, RefreshDatabase;

    private function seedEvent(Employee $employee): AttendanceEvent
    {
        $user = $employee->user;

        return AttendanceEvent::query()->create([
            'client_event_id' => (string) Str::uuid(),
            'employee_id' => $employee->id,
            'device_id' => Device::factory()->create(['employee_id' => $employee->id])->id,
            'event_type' => 'CHECK_IN',
            'event_at' => now(),
            'status' => 'ON_TIME',
            'sync_source' => 'mobile',
            'server_received_at' => now(),
        ]);
    }

    public function test_admin_can_view_attendance_list(): void
    {
        $admin = User::factory()->admin()->create();
        [, $employee] = $this->makeEmployeeUser();
        $this->seedEvent($employee);

        Livewire::actingAs($admin)
            ->test(ListAttendanceEvents::class)
            ->assertSuccessful()
            ->assertSee($employee->name);
    }

    public function test_hr_can_view_attendance_list(): void
    {
        $hr = User::factory()->hr()->create();
        [, $employee] = $this->makeEmployeeUser();
        $this->seedEvent($employee);

        Livewire::actingAs($hr)
            ->test(ListAttendanceEvents::class)
            ->assertSuccessful()
            ->assertSee($employee->name);
    }

    public function test_hr_cannot_delete_attendance(): void
    {
        $hr = User::factory()->hr()->create();
        [, $employee] = $this->makeEmployeeUser();
        $event = $this->seedEvent($employee);

        $this->actingAs($hr);

        $this->assertFalse($hr->can('delete', $event));
        $this->assertFalse($hr->can('update', $event));
        $this->assertFalse($hr->can('create', AttendanceEvent::class));
    }

    public function test_admin_cannot_modify_attendance_event(): void
    {
        $admin = User::factory()->admin()->create();
        [, $employee] = $this->makeEmployeeUser();
        $event = $this->seedEvent($employee);

        $this->actingAs($admin);

        $this->assertTrue($admin->can('viewAny', AttendanceEvent::class));
        $this->assertFalse($admin->can('update', $event));
        $this->assertFalse($admin->can('delete', $event));
        $this->assertFalse($admin->can('create', AttendanceEvent::class));
    }

    public function test_resource_has_no_create_permission(): void
    {
        $this->assertFalse(AttendanceEventResource::canCreate());
    }

    public function test_employee_cannot_manage_attendance_via_policy(): void
    {
        [$employeeUser, $employee] = $this->makeEmployeeUser();
        $event = $this->seedEvent($employee);

        $this->actingAs($employeeUser);

        $this->assertFalse($employeeUser->can('viewAny', AttendanceEvent::class));
        $this->assertFalse($employeeUser->can('view', $event));
    }
}

<?php

namespace Tests\Feature\Api\V1;

use App\Models\Branch;
use App\Models\Device;
use App\Models\Employee;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RelationshipTest extends TestCase
{
    use RefreshDatabase;

    public function test_employee_relationships_are_wired_correctly(): void
    {
        $branch = Branch::factory()->create();
        $user = User::factory()->create();
        $employee = Employee::factory()->create([
            'branch_id' => $branch->id,
            'user_id' => $user->id,
        ]);
        $device = Device::factory()->create(['employee_id' => $employee->id]);

        $this->assertTrue($employee->branch->is($branch));
        $this->assertTrue($employee->user->is($user));
        $this->assertTrue($employee->devices->contains($device));

        $this->assertTrue($branch->employees->contains($employee));
        $this->assertTrue($user->employee->is($employee));
        $this->assertTrue($device->employee->is($employee));

        $this->assertEquals('Asia/Makassar', $branch->timezone);
    }

    public function test_employee_belongs_to_nullable_relationships(): void
    {
        $employee = Employee::factory()->create([
            'branch_id' => null,
            'user_id' => null,
        ]);

        $this->assertNull($employee->branch);
        $this->assertNull($employee->user);
    }

    public function test_employee_has_many_devices(): void
    {
        $employee = Employee::factory()->create();
        Device::factory()->count(2)->create(['employee_id' => $employee->id]);

        $this->assertCount(2, $employee->devices);
        $this->assertDatabaseCount('devices', 2);
    }

    public function test_employee_deletion_is_soft(): void
    {
        $employee = Employee::factory()->create();

        $employee->delete();

        $this->assertSoftDeleted('employees', ['id' => $employee->id]);
        $this->assertDatabaseHas('employees', ['id' => $employee->id]);
    }

    public function test_employee_number_is_unique(): void
    {
        Employee::factory()->create(['employee_number' => 'EMP-1234']);

        $this->expectException(QueryException::class);

        Employee::factory()->create(['employee_number' => 'EMP-1234']);
    }
}

<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Employee;
use App\Models\User;

class EmployeePolicy
{
    public function viewAny(User $user): bool
    {
        return $this->isStaff($user);
    }

    public function view(User $user, Employee $employee): bool
    {
        return $this->isStaff($user);
    }

    public function create(User $user): bool
    {
        return $this->isStaff($user);
    }

    public function update(User $user, Employee $employee): bool
    {
        return $this->isStaff($user);
    }

    public function delete(User $user, Employee $employee): bool
    {
        return $user->role === UserRole::ADMIN;
    }

    public function restore(User $user, Employee $employee): bool
    {
        return $user->role === UserRole::ADMIN;
    }

    public function forceDelete(User $user, Employee $employee): bool
    {
        return false;
    }

    private function isStaff(User $user): bool
    {
        return in_array($user->role, [UserRole::ADMIN, UserRole::HR], true);
    }
}

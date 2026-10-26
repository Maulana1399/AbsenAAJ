<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Branch;
use App\Models\User;

class BranchPolicy
{
    public function viewAny(User $user): bool
    {
        return $this->isStaff($user);
    }

    public function view(User $user, Branch $branch): bool
    {
        return $this->isStaff($user);
    }

    public function create(User $user): bool
    {
        return $this->isStaff($user);
    }

    public function update(User $user, Branch $branch): bool
    {
        return $this->isStaff($user);
    }

    public function delete(User $user, Branch $branch): bool
    {
        return $user->role === UserRole::ADMIN;
    }

    public function deleteAny(User $user): bool
    {
        return $user->role === UserRole::ADMIN;
    }

    private function isStaff(User $user): bool
    {
        return in_array($user->role, [UserRole::ADMIN, UserRole::HR], true);
    }
}

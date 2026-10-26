<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\AttendanceEvent;
use App\Models\User;

class AttendanceEventPolicy
{
    /**
     * Attendance events are immutable: no one may create, edit, or delete
     * them through the panel. Corrections will be a separate feature.
     */
    public function viewAny(User $user): bool
    {
        return $this->isStaff($user);
    }

    public function view(User $user, AttendanceEvent $attendanceEvent): bool
    {
        return $this->isStaff($user);
    }

    public function create(User $user): bool
    {
        return false;
    }

    public function update(User $user, AttendanceEvent $attendanceEvent): bool
    {
        return false;
    }

    public function delete(User $user, AttendanceEvent $attendanceEvent): bool
    {
        return false;
    }

    public function forceDelete(User $user, AttendanceEvent $attendanceEvent): bool
    {
        return false;
    }

    private function isStaff(User $user): bool
    {
        return in_array($user->role, [UserRole::ADMIN, UserRole::HR], true);
    }
}

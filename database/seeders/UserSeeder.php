<?php

namespace Database\Seeders;

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Database\Seeder;

class UserSeeder extends Seeder
{
    /**
     * DEVELOPMENT-ONLY credentials.
     *
     * These users and passwords are for local development only and must
     * never be reused with the same values in a production deployment.
     */
    public function run(): void
    {
        User::query()->updateOrCreate(
            ['email' => 'admin@example.com'],
            [
                'name' => 'Admin',
                'role' => UserRole::ADMIN,
                'password' => 'password',
                'is_active' => true,
            ],
        );

        User::query()->updateOrCreate(
            ['email' => 'hr@example.com'],
            [
                'name' => 'HR',
                'role' => UserRole::HR,
                'password' => 'password',
                'is_active' => true,
            ],
        );
    }
}

<?php

namespace Database\Seeders;

use App\Models\Branch;
use Illuminate\Database\Seeder;

class BranchSeeder extends Seeder
{
    public function run(): void
    {
        Branch::query()->updateOrCreate(
            ['code' => 'HQ'],
            [
                'name' => 'Kantor Pusat',
                'timezone' => 'Asia/Makassar',
                'is_active' => true,
            ],
        );
    }
}

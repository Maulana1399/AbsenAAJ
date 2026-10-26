<?php

namespace Database\Factories;

use App\Models\Branch;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Branch>
 */
class BranchFactory extends Factory
{
    protected $model = Branch::class;

    public function definition(): array
    {
        return [
            'code' => fake()->unique()->lexify('BR-????'),
            'name' => fake()->company(),
            'latitude' => fake()->latitude(),
            'longitude' => fake()->longitude(),
            'radius_meters' => fake()->numberBetween(50, 500),
            'timezone' => 'Asia/Makassar',
            'is_active' => true,
        ];
    }
}

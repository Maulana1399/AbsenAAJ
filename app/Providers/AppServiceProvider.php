<?php

namespace App\Providers;

use App\Models\AttendanceEvent;
use App\Models\Branch;
use App\Models\Employee;
use App\Policies\AttendanceEventPolicy;
use App\Policies\BranchPolicy;
use App\Policies\EmployeePolicy;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Gate::policy(Employee::class, EmployeePolicy::class);
        Gate::policy(AttendanceEvent::class, AttendanceEventPolicy::class);
        Gate::policy(Branch::class, BranchPolicy::class);
    }
}

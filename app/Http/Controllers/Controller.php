<?php

namespace App\Http\Controllers;

use App\Exceptions\ApiException;
use App\Models\Employee;
use Illuminate\Http\Request;

abstract class Controller
{
    /**
     * Resolve the Employee linked to the authenticated user.
     *
     * The employee is always derived from the authenticated user, never
     * from client-submitted identifiers.
     */
    protected function authenticatedEmployee(Request $request): Employee
    {
        $employee = $request->user()->employee;

        if ($employee === null) {
            throw new ApiException(
                'Akun tidak terhubung ke data karyawan.',
                'EMPLOYEE_REQUIRED',
                403,
            );
        }

        return $employee;
    }
}

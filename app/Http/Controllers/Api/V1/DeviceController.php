<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\RegisterDeviceRequest;
use App\Http\Resources\Api\V1\DeviceResource;
use App\Services\AttendanceService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;

class DeviceController extends Controller
{
    public function __construct(private readonly AttendanceService $attendanceService) {}

    public function register(RegisterDeviceRequest $request): JsonResponse
    {
        $employee = $this->authenticatedEmployee($request);

        $device = $this->attendanceService->registerDevice($employee, $request->validated());

        return ApiResponse::success([
            'device' => DeviceResource::make($device),
        ]);
    }
}

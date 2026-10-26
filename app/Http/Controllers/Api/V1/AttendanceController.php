<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\ListAttendanceRequest;
use App\Http\Requests\Api\V1\StoreAttendanceEventRequest;
use App\Http\Resources\Api\V1\AttendanceEventResource;
use App\Services\AttendanceService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class AttendanceController extends Controller
{
    public function __construct(private readonly AttendanceService $attendanceService) {}

    public function store(StoreAttendanceEventRequest $request): JsonResponse
    {
        $employee = $this->authenticatedEmployee($request);

        $result = $this->attendanceService->recordEvent(
            $employee,
            $request->validated(),
            $request->file('photo'),
        );

        return ApiResponse::success(
            AttendanceEventResource::make($result['event']),
            $result['created'] ? 201 : 200,
        );
    }

    public function index(ListAttendanceRequest $request): AnonymousResourceCollection
    {
        $employee = $this->authenticatedEmployee($request);

        $events = $this->attendanceService->history(
            $employee,
            $request->validated('from'),
            $request->validated('to'),
        );

        return AttendanceEventResource::collection($events);
    }
}

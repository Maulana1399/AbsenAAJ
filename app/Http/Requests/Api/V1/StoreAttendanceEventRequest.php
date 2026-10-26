<?php

namespace App\Http\Requests\Api\V1;

use App\Enums\AttendanceEventType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreAttendanceEventRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $maxKb = (int) config('attendance.photo.max_kilobytes');
        $mimeTypes = implode(',', config('attendance.photo.mime_types'));

        return [
            'client_event_id' => ['required', 'string', 'max:100'],
            'device_uuid' => ['required', 'string', 'max:255'],
            'event_type' => ['required', Rule::enum(AttendanceEventType::class)],
            'event_at' => ['required', 'date'],

            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'accuracy_meters' => ['required', 'numeric', 'min:0'],

            'photo' => ['required', 'file', 'image', 'max:'.$maxKb, 'mimetypes:'.$mimeTypes],
            'captured_at' => ['nullable', 'date'],

            // Server-computed; the client is never allowed to influence them.
            'distance_meters' => ['prohibited'],
            'location_valid' => ['prohibited'],
            'status' => ['prohibited'],
            'employee_id' => ['prohibited'],
            'branch_id' => ['prohibited'],
            'sync_source' => ['prohibited'],
        ];
    }
}

<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AttendanceEventResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'client_event_id' => $this->client_event_id,
            'employee_id' => $this->employee_id,
            'device_id' => $this->device_id,
            'event_type' => $this->event_type,
            'status' => $this->status,
            'event_at' => $this->event_at?->toISOString(),
            'server_received_at' => $this->server_received_at?->toISOString(),
            'sync_source' => $this->sync_source,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            'accuracy_meters' => $this->accuracy_meters,
            'distance_meters' => $this->distance_meters,
            'location_valid' => $this->location_valid,
            'photo' => $this->whenLoaded('photo', fn () => $this->photo ? [
                'id' => $this->photo->id,
                'mime_type' => $this->photo->mime_type,
                'file_size' => $this->photo->file_size,
                'sha256' => $this->photo->sha256,
                'captured_at' => $this->photo->captured_at?->toISOString(),
            ] : null),
        ];
    }
}

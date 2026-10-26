<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DeviceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'device_uuid' => $this->device_uuid,
            'platform' => $this->platform,
            'manufacturer' => $this->manufacturer,
            'model' => $this->model,
            'app_version' => $this->app_version,
            'status' => $this->status,
            'registered_at' => $this->registered_at?->toISOString(),
            'last_seen_at' => $this->last_seen_at?->toISOString(),
        ];
    }
}

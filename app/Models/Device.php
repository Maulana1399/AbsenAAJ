<?php

namespace App\Models;

use App\Enums\DeviceStatus;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Device extends Model
{
    use HasFactory;

    protected $fillable = [
        'employee_id',
        'device_uuid',
        'platform',
        'manufacturer',
        'model',
        'app_version',
        'status',
        'registered_at',
        'last_seen_at',
    ];

    protected function casts(): array
    {
        return [
            'status' => DeviceStatus::class,
            'registered_at' => 'datetime',
            'last_seen_at' => 'datetime',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }
}

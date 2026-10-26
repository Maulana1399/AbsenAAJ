<?php

namespace App\Models;

use App\Enums\AttendanceEventType;
use App\Enums\AttendanceStatus;
use Database\Factories\AttendanceEventFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

class AttendanceEvent extends Model
{
    /** @use HasFactory<AttendanceEventFactory> */
    use HasFactory;

    protected $fillable = [
        'client_event_id',
        'employee_id',
        'device_id',
        'event_type',
        'event_at',
        'status',
        'sync_source',
        'server_received_at',
        'latitude',
        'longitude',
        'accuracy_meters',
        'distance_meters',
        'location_valid',
    ];

    protected function casts(): array
    {
        return [
            'event_type' => AttendanceEventType::class,
            'status' => AttendanceStatus::class,
            'event_at' => 'datetime',
            'server_received_at' => 'datetime',
            'latitude' => 'decimal:7',
            'longitude' => 'decimal:7',
            'accuracy_meters' => 'decimal:2',
            'distance_meters' => 'decimal:2',
            'location_valid' => 'boolean',
        ];
    }

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(Device::class);
    }

    public function photo(): HasOne
    {
        return $this->hasOne(AttendancePhoto::class);
    }
}

<?php

namespace App\Models;

use Database\Factories\AttendancePhotoFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AttendancePhoto extends Model
{
    /** @use HasFactory<AttendancePhotoFactory> */
    use HasFactory;

    protected $fillable = [
        'attendance_event_id',
        'storage_path',
        'original_filename',
        'mime_type',
        'file_size',
        'sha256',
        'captured_at',
    ];

    protected function casts(): array
    {
        return [
            'captured_at' => 'datetime',
        ];
    }

    public function attendanceEvent(): BelongsTo
    {
        return $this->belongsTo(AttendanceEvent::class);
    }
}

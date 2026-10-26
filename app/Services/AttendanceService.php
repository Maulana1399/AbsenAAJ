<?php

namespace App\Services;

use App\Enums\AttendanceEventType;
use App\Enums\AttendanceStatus;
use App\Enums\DeviceStatus;
use App\Exceptions\ApiException;
use App\Models\AttendanceEvent;
use App\Models\AttendancePhoto;
use App\Models\Branch;
use App\Models\Device;
use App\Models\Employee;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\QueryException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Throwable;

class AttendanceService
{
    /**
     * Register/refresh a device linked to the authenticated employee.
     *
     * Ownership is always derived from the authenticated employee, never
     * from the client.
     */
    public function registerDevice(Employee $employee, array $data): Device
    {
        $device = Device::query()->where('device_uuid', $data['device_uuid'])->first();

        if ($device !== null) {
            if ($device->employee_id !== $employee->id) {
                throw new ApiException(
                    'Device sudah terdaftar untuk karyawan lain.',
                    'DEVICE_ALREADY_REGISTERED',
                    409,
                );
            }

            if ($device->status === DeviceStatus::REVOKED) {
                throw new ApiException(
                    'Device telah direvoke dan tidak dapat didaftarkan ulang.',
                    'DEVICE_REVOKED',
                    403,
                );
            }

            $device->update([
                'platform' => $data['platform'],
                'manufacturer' => $data['manufacturer'] ?? $device->manufacturer,
                'model' => $data['model'] ?? $device->model,
                'app_version' => $data['app_version'] ?? $device->app_version,
                'last_seen_at' => now(),
            ]);

            return $device;
        }

        return DB::transaction(function () use ($employee, $data): Device {
            try {
                return Device::query()->create([
                    'employee_id' => $employee->id,
                    'device_uuid' => $data['device_uuid'],
                    'platform' => $data['platform'],
                    'manufacturer' => $data['manufacturer'] ?? null,
                    'model' => $data['model'] ?? null,
                    'app_version' => $data['app_version'] ?? null,
                    'status' => DeviceStatus::ACTIVE,
                    'registered_at' => now(),
                    'last_seen_at' => now(),
                ]);
            } catch (QueryException $e) {
                if ($this->isDuplicateKeyError($e)) {
                    return Device::query()
                        ->where('device_uuid', $data['device_uuid'])
                        ->firstOrFail();
                }

                throw $e;
            }
        });
    }

    /**
     * Record a check-in / check-out event with photo and GPS.
     *
     * The server clock is authoritative for attendance time. The client
     * event_at is accepted for backward compatibility but is never used.
     *
     * @return array{event: AttendanceEvent, created: bool}
     */
    public function recordEvent(Employee $employee, array $data, UploadedFile $photo): array
    {
        // Idempotency first: a replayed request returns the existing event
        // without storing a duplicate photo (or an orphan file).
        $existing = AttendanceEvent::query()
            ->where('client_event_id', $data['client_event_id'])
            ->first();

        if ($existing !== null) {
            return [
                'event' => $this->resolveExistingEventFor($employee, $existing)->load('photo'),
                'created' => false,
            ];
        }

        $recordedAt = now();
        $device = $this->resolveActiveDevice($employee, $data['device_uuid']);

        $eventType = AttendanceEventType::from($data['event_type']);

        $branch = $this->resolveBranch($employee);

        $this->assertAccuracy((float) $data['accuracy_meters']);

        $distance = $this->distanceMeters(
            (float) $data['latitude'],
            (float) $data['longitude'],
            (float) $branch->latitude,
            (float) $branch->longitude,
        );

        if ($distance > (float) $branch->radius_meters) {
            throw new ApiException(
                'Lokasi anda berada di luar area branch.',
                'OUTSIDE_GEOFENCE',
                422,
            );
        }

        $this->assertSequence($employee, $eventType);

        $status = $this->calculateStatus($eventType, $recordedAt);

        $path = null;

        try {
            $path = $this->storePhotoFile($employee, $device, $photo, $recordedAt);
            $sha256 = hash_file('sha256', Storage::disk('local')->path($path));

            [$event, $created] = DB::transaction(function () use (
                $employee,
                $device,
                $data,
                $eventType,
                $recordedAt,
                $status,
                $path,
                $sha256,
                $photo,
                $distance,
            ): array {
                try {
                    $event = AttendanceEvent::query()->create([
                        'client_event_id' => $data['client_event_id'],
                        'employee_id' => $employee->id,
                        'device_id' => $device->id,
                        'event_type' => $eventType,
                        'event_at' => $recordedAt,
                        'status' => $status,
                        'sync_source' => 'mobile',
                        'server_received_at' => $recordedAt,
                        'latitude' => $data['latitude'],
                        'longitude' => $data['longitude'],
                        'accuracy_meters' => $data['accuracy_meters'],
                        'distance_meters' => round($distance, 2),
                        'location_valid' => true,
                    ]);

                    AttendancePhoto::query()->create([
                        'attendance_event_id' => $event->id,
                        'storage_path' => $path,
                        'original_filename' => $photo->getClientOriginalName(),
                        'mime_type' => (string) $photo->getMimeType(),
                        'file_size' => $photo->getSize(),
                        'sha256' => $sha256,
                        'captured_at' => isset($data['captured_at'])
                            ? Carbon::parse($data['captured_at'])
                            : null,
                    ]);

                    return [$event, true];
                } catch (QueryException $e) {
                    if ($this->isDuplicateKeyError($e)) {
                        Storage::disk('local')->delete($path);

                        $existing = AttendanceEvent::query()
                            ->where('client_event_id', $data['client_event_id'])
                            ->firstOrFail();

                        return [$this->resolveExistingEventFor($employee, $existing), false];
                    }

                    throw $e;
                }
            });

            if ($created) {
                $device->update(['last_seen_at' => $recordedAt]);
            }

            return ['event' => $event->load('photo'), 'created' => $created];
        } catch (ApiException $e) {
            if ($path !== null) {
                Storage::disk('local')->delete($path);
            }

            throw $e;
        } catch (Throwable $e) {
            if ($path !== null) {
                Storage::disk('local')->delete($path);
            }

            throw $e;
        }
    }

    /**
     * Attendance history for a single employee, optionally filtered by
     * inclusive date range (in the attendance timezone).
     */
    public function history(Employee $employee, ?string $from = null, ?string $to = null): Collection
    {
        $query = AttendanceEvent::query()
            ->with('photo')
            ->where('employee_id', $employee->id);

        if ($from !== null) {
            $query->where(
                'event_at',
                '>=',
                Carbon::parse($from, config('attendance.timezone'))->startOfDay()->utc(),
            );
        }

        if ($to !== null) {
            $query->where(
                'event_at',
                '<=',
                Carbon::parse($to, config('attendance.timezone'))->endOfDay()->utc(),
            );
        }

        return $query->latest('event_at')->get();
    }

    private function resolveExistingEventFor(Employee $employee, AttendanceEvent $event): AttendanceEvent
    {
        if ($event->employee_id !== $employee->id) {
            throw new ApiException(
                'client_event_id sudah digunakan oleh event lain.',
                'ATTENDANCE_EVENT_CONFLICT',
                409,
            );
        }

        return $event;
    }

    private function resolveActiveDevice(Employee $employee, string $deviceUuid): Device
    {
        $device = Device::query()
            ->where('employee_id', $employee->id)
            ->where('device_uuid', $deviceUuid)
            ->first();

        if ($device === null) {
            throw new ApiException(
                'Device tidak ditemukan atau belum terdaftar.',
                'DEVICE_NOT_FOUND',
                404,
            );
        }

        if ($device->status === DeviceStatus::REVOKED) {
            throw new ApiException(
                'Device telah direvoke.',
                'DEVICE_REVOKED',
                403,
            );
        }

        return $device;
    }

    private function resolveBranch(Employee $employee): Branch
    {
        $branch = $employee->branch;

        if ($branch === null) {
            throw new ApiException(
                'Branch belum dikonfigurasi untuk karyawan.',
                'BRANCH_NOT_CONFIGURED',
                422,
            );
        }

        if ($branch->latitude === null || $branch->longitude === null || $branch->radius_meters === null) {
            throw new ApiException(
                'Branch belum memiliki konfigurasi lokasi.',
                'BRANCH_LOCATION_NOT_CONFIGURED',
                422,
            );
        }

        return $branch;
    }

    private function assertAccuracy(float $accuracyMeters): void
    {
        $max = (float) config('attendance.location_max_accuracy_meters');

        if ($accuracyMeters > $max) {
            throw new ApiException(
                'Akurasi GPS terlalu rendah. Coba lagi di tempat yang lebih terbuka.',
                'LOCATION_LOW_ACCURACY',
                422,
            );
        }
    }

    private function storePhotoFile(Employee $employee, Device $device, UploadedFile $photo, Carbon $recordedAt): string
    {
        $extension = $this->photoExtension($photo);
        $directory = sprintf(
            'attendance/%d/%s/%s',
            $employee->id,
            $recordedAt->format('Y'),
            $recordedAt->format('m'),
        );
        $filename = sprintf('%s-%s.%s', $device->id, (string) Str::uuid(), $extension);

        $path = Storage::disk('local')->putFileAs($directory, $photo, $filename);

        if ($path === false) {
            throw new ApiException(
                'Gagal menyimpan foto.',
                'PHOTO_STORE_FAILED',
                500,
            );
        }

        return $path;
    }

    private function photoExtension(UploadedFile $photo): string
    {
        return match ($photo->getMimeType()) {
            'image/png' => 'png',
            'image/webp' => 'webp',
            default => 'jpg',
        };
    }

    private function distanceMeters(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6371000.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);

        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLon / 2) ** 2;

        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return $earthRadius * $c;
    }

    private function assertSequence(Employee $employee, AttendanceEventType $type): void
    {
        $latest = AttendanceEvent::query()
            ->where('employee_id', $employee->id)
            ->latest('server_received_at')
            ->latest('id')
            ->first();

        if ($type === AttendanceEventType::CHECK_IN) {
            if ($latest !== null && $latest->event_type === AttendanceEventType::CHECK_IN) {
                throw new ApiException(
                    'Employee sudah melakukan check-in.',
                    'ALREADY_CHECKED_IN',
                    422,
                );
            }

            return;
        }

        if ($latest === null) {
            throw new ApiException(
                'Check-out membutuhkan check-in terlebih dahulu.',
                'CHECK_IN_REQUIRED',
                422,
            );
        }

        if ($latest->event_type !== AttendanceEventType::CHECK_IN) {
            throw new ApiException(
                'Employee sudah melakukan check-out.',
                'ALREADY_CHECKED_OUT',
                422,
            );
        }
    }

    private function calculateStatus(AttendanceEventType $type, Carbon $recordedAt): AttendanceStatus
    {
        $local = $recordedAt->copy()->setTimezone(config('attendance.timezone'));

        if ($type === AttendanceEventType::CHECK_IN) {
            $cutoff = $this->localTime($local->toDateString(), config('attendance.shift.start'))
                ->addMinutes((int) config('attendance.shift.grace_minutes'));

            return $local->lte($cutoff) ? AttendanceStatus::ON_TIME : AttendanceStatus::LATE;
        }

        $end = $this->localTime($local->toDateString(), config('attendance.shift.end'));

        return $local->lt($end) ? AttendanceStatus::EARLY_CHECKOUT : AttendanceStatus::NORMAL;
    }

    private function localTime(string $date, string $time): Carbon
    {
        return Carbon::parse("{$date} {$time}", config('attendance.timezone'));
    }

    private function isDuplicateKeyError(QueryException $e): bool
    {
        return $e->errorInfo[1] === 1062;
    }
}

<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AttendanceEvent;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

class AttendancePhotoController extends Controller
{
    public function __invoke(AttendanceEvent $attendanceEvent): StreamedResponse
    {
        Gate::authorize('view', $attendanceEvent);

        $photo = $attendanceEvent->photo;

        abort_if($photo === null, 404, 'Foto selfie tidak tersedia untuk event ini.');

        $disk = Storage::disk('local');

        abort_unless($disk->exists($photo->storage_path), 404, 'File foto selfie tidak ditemukan.');

        return $disk->response($photo->storage_path, $photo->original_filename, [
            'Cache-Control' => 'private, max-age=300',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }
}

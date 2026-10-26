<?php

use App\Http\Controllers\Admin\AttendancePhotoController;
use Filament\Http\Middleware\Authenticate;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::middleware([Authenticate::class])
    ->prefix('admin')
    ->name('admin.')
    ->group(function (): void {
        Route::get('/attendance-events/{attendanceEvent}/photo', AttendancePhotoController::class)
            ->name('attendance-events.photo');
    });

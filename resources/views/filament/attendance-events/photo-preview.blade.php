<div class="space-y-4 text-sm">
    @if ($photo === null)
        <p class="text-gray-500 dark:text-gray-400">
            Event ini tidak memiliki foto selfie.
        </p>
    @elseif ($url === null)
        <div class="rounded-lg bg-danger-50 p-4 text-danger-700 dark:bg-danger-500/10 dark:text-danger-400">
            File foto selfie tidak ditemukan pada penyimpanan.
        </div>

        <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div>
                <dt class="font-medium text-gray-500 dark:text-gray-400">Nama File</dt>
                <dd class="break-all">{{ $photo->original_filename ?? '—' }}</dd>
            </div>
            <div>
                <dt class="font-medium text-gray-500 dark:text-gray-400">Tipe</dt>
                <dd>{{ $photo->mime_type }}</dd>
            </div>
            <div>
                <dt class="font-medium text-gray-500 dark:text-gray-400">Ukuran</dt>
                <dd>{{ number_format((int) $photo->file_size) }} byte</dd>
            </div>
            <div class="sm:col-span-2">
                <dt class="font-medium text-gray-500 dark:text-gray-400">SHA-256</dt>
                <dd class="break-all font-mono text-xs">{{ $photo->sha256 }}</dd>
            </div>
        </dl>
    @else
        <img
            src="{{ $url }}"
            alt="Foto selfie {{ $photo->original_filename ?? 'absensi' }}"
            class="mx-auto max-h-[70vh] w-auto rounded-lg object-contain"
        >

        <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div>
                <dt class="font-medium text-gray-500 dark:text-gray-400">Nama File</dt>
                <dd class="break-all">{{ $photo->original_filename ?? '—' }}</dd>
            </div>
            <div>
                <dt class="font-medium text-gray-500 dark:text-gray-400">Tipe</dt>
                <dd>{{ $photo->mime_type }}</dd>
            </div>
            <div>
                <dt class="font-medium text-gray-500 dark:text-gray-400">Ukuran</dt>
                <dd>{{ number_format((int) $photo->file_size) }} byte</dd>
            </div>
            <div>
                <dt class="font-medium text-gray-500 dark:text-gray-400">Diambil</dt>
                <dd>{{ $photo->captured_at?->format('d M Y H:i:s') ?? '—' }}</dd>
            </div>
            <div class="sm:col-span-2">
                <dt class="font-medium text-gray-500 dark:text-gray-400">SHA-256</dt>
                <dd class="break-all font-mono text-xs">{{ $photo->sha256 }}</dd>
            </div>
        </dl>
    @endif
</div>

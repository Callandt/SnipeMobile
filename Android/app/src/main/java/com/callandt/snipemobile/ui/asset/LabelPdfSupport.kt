package com.callandt.snipemobile.ui.asset

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.callandt.snipemobile.ui.util.L10n
import java.io.File
import java.util.UUID

/** Cache label PDFs and open/share them via FileProvider. */
object LabelPdfSupport {
    fun writeTemporaryPdf(context: Context, bytes: ByteArray, preferredName: String = "labels"): File? {
        return runCatching {
            val dir = File(context.cacheDir, "labels").apply { mkdirs() }
            val file = File(dir, "$preferredName-${UUID.randomUUID()}.pdf")
            file.writeBytes(bytes)
            file
        }.getOrNull()
    }

    private fun contentUri(context: Context, file: File) =
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)

    /** Open the PDF with ACTION_VIEW. */
    fun openPdf(context: Context, file: File): Boolean {
        val uri = contentUri(context, file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/pdf")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            context.startActivity(Intent.createChooser(intent, L10n.string("asset_labels")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            true
        }.getOrDefault(false)
    }

    /** Share the PDF. */
    fun sharePdf(context: Context, file: File) {
        val uri = contentUri(context, file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching {
            context.startActivity(Intent.createChooser(intent, L10n.string("share")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        }
    }
}

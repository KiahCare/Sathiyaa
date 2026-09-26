// `in` is a reserved word in Kotlin, so the package line has to escape it
// with backticks. The application id `in.sathiyaa.customer` is fine as it is --
// that is an Android identifier, not Kotlin source -- but this file is
// compiled by kotlinc, which rejects a bare `in` with:
//   error: Package name must be a '.'-separated identifier list.
package `in`.sathiyaa.customer

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()

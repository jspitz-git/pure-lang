# pure-odbc on native Windows

## Supported ODBC layer

The Windows bundle uses the native Microsoft ODBC Driver Manager provided by
`C:\Windows\System32\odbc32.dll`. It does not bundle unixODBC.

The CLANG64 toolchain supplies the matching Windows API declarations and
import library:

- `sql.h` comes from the mingw-w64 Windows headers package;
- `libodbc32.a` comes from the mingw-w64 CRT package;
- the loaded `odbc32.dll` is the 64-bit Windows system component.

This choice avoids a second driver-manager configuration, duplicate DSN and
driver registries, and an additional runtime DLL. It also lets Pure use the
same 64-bit drivers and DSNs as other native Windows applications.

## Driver support

The bundle contains the driver manager and the Pure binding, not database
drivers. Installing and configuring a suitable 64-bit ODBC driver remains the
user's responsibility. A driver must match the architecture of `pure.exe`.

Automated tests always exercise driver-manager allocation, enumeration, and
diagnostics without credentials or a machine-specific DSN. When the exact
64-bit `Microsoft Access Text Driver (*.txt, *.csv)` is registered, the tests
also create a temporary local CSV data source and validate statements,
parameters, and result conversion. This local observation does not imply
support for other Microsoft Access drivers, MySQL, SQL Server, or any other
third-party driver.

unixODBC remains the appropriate implementation for Unix-like platforms but
is deliberately outside the native Windows bundle.

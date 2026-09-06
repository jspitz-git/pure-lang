#include <libxml/parser.h>

int main(void) {
  /* libxml2 2.15 removed the built-in HTTP and FTP clients. */
  if (xmlHasFeature(XML_WITH_HTTP) || xmlHasFeature(XML_WITH_FTP))
    return 1;
  return 0;
}

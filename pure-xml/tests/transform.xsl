<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" encoding="UTF-8" omit-xml-declaration="yes"/>
  <xsl:template match="/">
    <summary>
      <xsl:value-of select="count(catalog/item)"/>
      <xsl:text> položky</xsl:text>
    </summary>
  </xsl:template>
</xsl:stylesheet>

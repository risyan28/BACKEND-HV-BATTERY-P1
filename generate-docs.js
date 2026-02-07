/**
 * Document Generator for Backend Runtime Maintenance Guide
 * Generates DOCX and PDF versions from markdown source
 */

const fs = require('fs')
const path = require('path')

// Read the markdown file
const markdownFile = path.join(
  __dirname,
  'backend_runtime_maintenance_guide.md',
)
const markdown = fs.readFileSync(markdownFile, 'utf8')

console.log('📄 Starting document generation...\n')

// ============================================
// DOCX Generation (Manual - Simple HTML approach)
// ============================================
async function generateDOCX() {
  console.log('📝 Generating DOCX...')

  try {
    // Convert markdown to HTML-like format for Word
    let html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <title>Backend Runtime Maintenance Guide</title>
  <style>
    body { 
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
      line-height: 1.6; 
      max-width: 800px; 
      margin: 40px auto; 
      padding: 20px;
    }
    h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
    h2 { color: #34495e; border-bottom: 2px solid #95a5a6; padding-bottom: 8px; margin-top: 30px; }
    h3 { color: #7f8c8d; }
    code { 
      background-color: #f4f4f4; 
      border: 1px solid #ddd; 
      border-radius: 4px; 
      padding: 2px 6px; 
      font-family: 'Consolas', 'Courier New', monospace;
      font-size: 90%;
    }
    pre { 
      background-color: #2d2d2d; 
      color: #f8f8f2; 
      border-radius: 6px; 
      padding: 15px; 
      overflow-x: auto;
      font-family: 'Consolas', 'Courier New', monospace;
      line-height: 1.4;
    }
    pre code {
      background: none;
      border: none;
      color: inherit;
      padding: 0;
    }
    blockquote {
      border-left: 4px solid #3498db;
      margin: 20px 0;
      padding: 10px 20px;
      background-color: #ecf0f1;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin: 20px 0;
    }
    th, td {
      border: 1px solid #bdc3c7;
      padding: 12px;
      text-align: left;
    }
    th {
      background-color: #34495e;
      color: white;
    }
    .emoji {
      font-size: 1.2em;
    }
    .success { color: #27ae60; }
    .error { color: #e74c3c; }
    .warning { color: #f39c12; }
    .info { color: #3498db; }
  </style>
</head>
<body>
`

    // Simple markdown to HTML conversion
    let content = markdown
      // Headings
      .replace(/^# (.*$)/gim, '<h1>$1</h1>')
      .replace(/^## (.*$)/gim, '<h2>$1</h2>')
      .replace(/^### (.*$)/gim, '<h3>$1</h3>')
      .replace(/^#### (.*$)/gim, '<h4>$1</h4>')
      // Bold
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      // Italic
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      // Code blocks
      .replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>')
      // Inline code
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      // Links
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
      // Horizontal rules
      .replace(/^---$/gim, '<hr>')
      // Line breaks
      .replace(/\n\n/g, '</p><p>')
      // Lists
      .replace(/^\* (.*$)/gim, '<li>$1</li>')
      .replace(/^\- (.*$)/gim, '<li>$1</li>')
      .replace(/^(\d+)\. (.*$)/gim, '<li>$2</li>')

    html += `<p>${content}</p>`
    html += `
</body>
</html>
`

    // Save as MHTML (can be opened in Word)
    const docxFile = path.join(
      __dirname,
      'backend_runtime_maintenance_guide.mhtml',
    )
    fs.writeFileSync(docxFile, html, 'utf8')

    console.log(`✅ DOCX-compatible file created: ${docxFile}`)
    console.log('   📌 Open with Microsoft Word and save as .docx\n')

    return docxFile
  } catch (error) {
    console.error('❌ DOCX generation failed:', error.message)
    return null
  }
}

// ============================================
// PDF Generation (Manual - HTML to self-styled)
// ============================================
async function generatePDF() {
  console.log('📕 Generating PDF-ready HTML...')

  try {
    // Same HTML generation as above
    let html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Backend Runtime Maintenance Guide</title>
  <style>
    @page { 
      size: A4; 
      margin: 2cm; 
    }
    body { 
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
      line-height: 1.6; 
      color: #333;
      font-size: 11pt;
    }
    h1 { 
      color: #2c3e50; 
      border-bottom: 3px solid #3498db; 
      padding-bottom: 10px; 
      page-break-after: avoid;
      font-size: 24pt;
    }
    h2 { 
      color: #34495e; 
      border-bottom: 2px solid #95a5a6; 
      padding-bottom: 8px; 
      margin-top: 30px;
      page-break-after: avoid;
      font-size: 18pt;
    }
    h3 { 
      color: #7f8c8d; 
      page-break-after: avoid;
      font-size: 14pt;
    }
    code { 
      background-color: #f4f4f4; 
      border: 1px solid #ddd; 
      border-radius: 4px; 
      padding: 2px 6px; 
      font-family: 'Consolas', 'Courier New', monospace;
      font-size: 9pt;
    }
    pre { 
      background-color: #2d2d2d; 
      color: #f8f8f2; 
      border-radius: 6px; 
      padding: 15px; 
      overflow-x: auto;
      font-family: 'Consolas', 'Courier New', monospace;
      line-height: 1.4;
      page-break-inside: avoid;
      font-size: 9pt;
    }
    pre code {
      background: none;
      border: none;
      color: inherit;
      padding: 0;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin: 20px 0;
      page-break-inside: avoid;
    }
    th, td {
      border: 1px solid #bdc3c7;
      padding: 12px;
      text-align: left;
      font-size: 10pt;
    }
    th {
      background-color: #34495e;
      color: white;
    }
    .page-break { page-break-after: always; }
  </style>
</head>
<body>
`

    // Same conversion
    let content = markdown
      .replace(/^# (.*$)/gim, '<h1>$1</h1>')
      .replace(/^## (.*$)/gim, '<h2>$1</h2>')
      .replace(/^### (.*$)/gim, '<h3>$1</h3>')
      .replace(/^#### (.*$)/gim, '<h4>$1</h4>')
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>')
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
      .replace(/^---$/gim, '<hr>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/^\* (.*$)/gim, '<li>$1</li>')
      .replace(/^\- (.*$)/gim, '<li>$1</li>')
      .replace(/^(\d+)\. (.*$)/gim, '<li>$2</li>')

    html += `<p>${content}</p>`
    html += `
</body>
</html>
`

    const pdfFile = path.join(
      __dirname,
      'backend_runtime_maintenance_guide.html',
    )
    fs.writeFileSync(pdfFile, html, 'utf8')

    console.log(`✅ PDF-ready HTML created: ${pdfFile}`)
    console.log('   📌 Open in browser, Ctrl+P, "Save as PDF"\n')

    return pdfFile
  } catch (error) {
    console.error('❌ PDF generation failed:', error.message)
    return null
  }
}

// ============================================
// Main Execution
// ============================================
async function main() {
  console.log('🚀 Backend Runtime Maintenance Guide - Document Generator\n')
  console.log(`📄 Source file: ${markdownFile}\n`)

  const results = await Promise.all([generateDOCX(), generatePDF()])

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
  console.log('✅ Document generation complete!\n')

  console.log('📦 Generated files:')
  if (results[0]) console.log(`   • DOCX: ${path.basename(results[0])}`)
  if (results[1]) console.log(`   • PDF:  ${path.basename(results[1])}`)

  console.log('\n📝 Manual steps:')
  console.log('   1. Open .mhtml file with Microsoft Word')
  console.log('   2. File → Save As → .docx format')
  console.log('   3. Open .html file in Chrome/Edge')
  console.log('   4. Ctrl+P → Save as PDF\n')
}

main().catch(console.error)

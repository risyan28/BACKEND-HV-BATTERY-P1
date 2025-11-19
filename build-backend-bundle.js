// build-backend-bundle.js
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const os = require("os");

const ROOT = process.cwd();
const DIST = path.join(ROOT, "dist");
const PACKAGE_JSON = path.join(ROOT, "package.json");
const PRISMA_DIR = path.join(ROOT, "prisma");
const ENV_FILE = path.join(ROOT, ".env"); // Ganti ke .env.production jika kamu punya
const TARGET = path.join(ROOT, "backend-runtime"); // Nama folder output
const ZIP_FILE = path.join(ROOT, "backend-runtime.zip"); // Nama file zip output

function run(cmd, cwd = ROOT) {
  console.log(`> ${cmd}`);
  execSync(cmd, { stdio: "inherit", cwd, shell: true }); // Gunakan shell agar perintah windows seperti xcopy berfungsi
}

function copyRecursive(src, dest) {
  const exists = fs.existsSync(src);
  if (!exists) {
    console.log(`⚠️ Source path does not exist: ${src}`);
    return;
  }

  const stats = fs.statSync(src);
  const isDirectory = stats.isDirectory();

  if (isDirectory) {
    if (!fs.existsSync(dest)) {
      fs.mkdirSync(dest, { recursive: true });
    }
    fs.readdirSync(src).forEach((childItemName) => {
      copyRecursive(
        path.join(src, childItemName),
        path.join(dest, childItemName)
      );
    });
  } else {
    fs.copyFileSync(src, dest);
  }
}

console.log("📦 Starting Backend Runtime Bundle Creation...\n");

try {
  // 1. Pastikan dist/ dan prisma/ siap
  console.log("🔍 Step 1: Ensuring build artifacts are up-to-date...");
  run("npm run build"); // Jalankan build

  // 2. Bersihkan folder target lama jika ada
  console.log("\n🧹 Step 2: Cleaning up previous build...");
  if (fs.existsSync(TARGET)) {
    fs.rmSync(TARGET, { recursive: true, force: true });
    console.log(`   Removed old ${TARGET}`);
  }
  fs.mkdirSync(TARGET, { recursive: true });
  console.log(`   Created fresh ${TARGET}`);

  // 3. Copy dist/, prisma/, package.json, .env
  console.log("\n📂 Step 3: Copying necessary files...");

  console.log("   - Copying dist/");
  copyRecursive(DIST, path.join(TARGET, "dist"));

  if (fs.existsSync(PRISMA_DIR)) {
    console.log("   - Copying prisma/");
    copyRecursive(PRISMA_DIR, path.join(TARGET, "prisma"));
  } else {
    console.warn("   ⚠️ Prisma directory not found, skipping.");
  }

  console.log("   - Copying package.json");
  fs.copyFileSync(PACKAGE_JSON, path.join(TARGET, "package.json"));

  if (fs.existsSync(ENV_FILE)) {
    console.log("   - Copying .env");
    fs.copyFileSync(ENV_FILE, path.join(TARGET, ".env"));
  } else {
    console.warn("   ⚠️ .env file not found in root, skipping. Remember to set environment variables on the server.");
  }

  // 4. Install production dependencies di folder runtime
  console.log("\n📦 Step 4: Installing production dependencies in runtime folder...");
  run("npm install --omit=dev", TARGET); // Install di dalam folder target
  run("npx prisma generate", TARGET); // Generate Prisma Client di dalam folder target


/*   // 5. (Opsional) Zip folder runtime
  console.log("\n_compressing: Creating ZIP archive...");
  // Gunakan `zip` di Unix/Linux/macOS, `7z` atau `powershell` di Windows
  let zipCmd;
  if (os.platform() === "win32") {
    // Gunakan powershell Compress-Archive
    zipCmd = `powershell -Command "Compress-Archive -Path '${TARGET}' -DestinationPath '${ZIP_FILE}' -Force"`;
  } else {
    // Gunakan perintah zip standar
    zipCmd = `zip -r ${ZIP_FILE} ${path.basename(TARGET)}`;
  }
  run(zipCmd, path.dirname(TARGET)); // Eksekusi dari parent directory agar nama folder masuk ke zip */

  console.log("\n✅ Success!");
  console.log(`   - Backend runtime bundle is ready in: ${TARGET}`);
  console.log(`   - ZIP archive is ready: ${ZIP_FILE}`);
  console.log("\n📋 Next Steps:");
  console.log(`   1. Copy '${ZIP_FILE}' to your production server.`);
  console.log(`   2. Extract it on the server (e.g., 'unzip backend-runtime.zip').`);
  console.log(`   3. Navigate to the extracted folder.`);
  console.log(`   4. Ensure Node.js and PM2 are installed on the server.`);
  console.log(`   5. Run: 'pm2 start dist/index.js --name \"my-backend-app\" --time'`);
  console.log(`   6. (Optional) Run: 'pm2 startup' and 'pm2 save' for auto-start.`);

} catch (error) {
  console.error("\n❌ An error occurred during the build process:");
  console.error(error.message);
  process.exit(1);
}
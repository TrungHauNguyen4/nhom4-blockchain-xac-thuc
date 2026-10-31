import hre from "hardhat";
import fs from "fs";

async function main() {
  console.log("Đang biên dịch và triển khai Smart Contract lên mạng Sepolia...");
  
  // Lấy Factory của Contract
  const Registry = await hre.ethers.getContractFactory("SignedRecordRegistry");
  
  // Khởi tạo giao dịch Deploy
  const registry = await Registry.deploy();
  
  console.log("Đang chờ mạng lưới xác nhận (mining)...");
  await registry.waitForDeployment();
  
  const address = await registry.getAddress();
  
  console.log(`\n✅ Triển khai thành công!`);
  console.log(`📍 Địa chỉ Contract thật: ${address}`);

  // Tự động cập nhật file .env
  let envContent = fs.readFileSync(".env", "utf8");
  envContent = envContent.replace(/CONTRACT_ADDRESS=.*/g, `CONTRACT_ADDRESS=${address}`);
  fs.writeFileSync(".env", envContent);
  console.log(`✅ Đã tự động cập nhật file .env! Bạn hãy khởi động lại server.js là xong!`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

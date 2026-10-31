import { ethers } from 'ethers';

// Kiểm tra xem MetaMask đã được cài đặt chưa
export const checkMetaMaskInstalled = (): boolean => {
  return typeof window !== 'undefined' && typeof window.ethereum !== 'undefined';
};

// Kết nối ví MetaMask
export const connectWallet = async () => {
  if (!checkMetaMaskInstalled()) {
    throw new Error('Vui lòng cài đặt MetaMask!');
  }
  
  try {
    const provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send('eth_requestAccounts', []);
    const signer = await provider.getSigner();
    const address = await signer.getAddress();
    
    // Tùy chọn: Kiểm tra xem có đang ở Sepolia network không (Chain ID 11155111)
    const network = await provider.getNetwork();
    
    return {
      provider,
      signer,
      address,
      chainId: network.chainId
    };
  } catch (error) {
    console.error('Lỗi khi kết nối ví:', error);
    throw error;
  }
};

// Ký trực tiếp một đoạn Hash (dùng chung cho File và Text)
export const signHashMessage = async (signer: ethers.JsonRpcSigner, hash: string) => {
  try {
    // Ở frontend, signMessage sẽ tự động thêm prefix chuẩn \x19Ethereum Signed Message:\n
    // Yêu cầu phải chuyển hash dạng string ('0x...') thành mảng bytes để tránh bị hiểu nhầm là text
    const signature = await signer.signMessage(ethers.getBytes(hash));
    return signature;
  } catch (error) {
    console.error('Lỗi khi ký Hash:', error);
    throw error;
  }
};

// Băm dữ liệu Text
export const hashText = (data: string): string => {
  return ethers.keccak256(ethers.toUtf8Bytes(data));
};

// Đọc File và Băm bằng Keccak256
export const hashFileContent = async (file: File): Promise<string> => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      if (e.target?.result) {
        const buffer = e.target.result as ArrayBuffer;
        // Chuyển ArrayBuffer của file thành mảng byte chuẩn, sau đó băm
        const hash = ethers.keccak256(new Uint8Array(buffer));
        resolve(hash);
      } else {
        reject(new Error("Không thể đọc nội dung file"));
      }
    };
    reader.onerror = () => reject(new Error("Đã xảy ra lỗi khi đọc file"));
    reader.readAsArrayBuffer(file);
  });
};

// Ký một đoạn dữ liệu Text thô (Hỗ trợ luồng cũ)
export const signDataMessage = async (signer: ethers.JsonRpcSigner, data: string) => {
  try {
    const dataHash = hashText(data);
    const signature = await signHashMessage(signer, dataHash);
    
    return {
      dataHash,
      signature
    };
  } catch (error) {
    console.error('Lỗi khi ký dữ liệu:', error);
    throw error;
  }
};

// ABI của Hợp đồng SignedRecordRegistry
export const contractABI = [
  "function submitSignedRecord(bytes32 dataHash, bytes signature) external",
  "function getRecord(bytes32 dataHash) external view returns (tuple(bytes32 dataHash, address signer, uint256 timestamp))",
  "event RecordSigned(address indexed signer, bytes32 indexed dataHash, uint256 timestamp)"
];

// Hàm gửi giao dịch lên Blockchain (Tốn phí gas)
export const submitToBlockchain = async (
  signer: ethers.JsonRpcSigner, 
  contractAddress: string, 
  dataHash: string, 
  signature: string
) => {
  try {
    const contract = new ethers.Contract(contractAddress, contractABI, signer);
    // Gọi hàm submitSignedRecord của Smart Contract
    const tx = await contract.submitSignedRecord(dataHash, signature);
    // Chờ giao dịch được xác nhận trên mạng
    const receipt = await tx.wait();
    return receipt;
  } catch (error) {
    console.error('Lỗi khi lưu lên Blockchain:', error);
    throw error;
  }
};

// Hàm đọc dữ liệu từ Blockchain (Không tốn phí gas)
export const verifyFromBlockchain = async (
  provider: ethers.BrowserProvider,
  contractAddress: string,
  dataHash: string
) => {
  try {
    const contract = new ethers.Contract(contractAddress, contractABI, provider);
    const result = await contract.getRecord(dataHash);
    
    // Nếu signer là địa chỉ rỗng, tức là chưa có dữ liệu
    if (result.signer === "0x0000000000000000000000000000000000000000") {
      return null;
    }
    
    return {
      dataHash: result.dataHash,
      signer: result.signer,
      timestamp: Number(result.timestamp)
    };
  } catch (error) {
    console.error('Lỗi khi đọc Blockchain:', error);
    throw error;
  }
};

// Hàm tiện ích: Cắt gọn địa chỉ ví cho đẹp UI (0x1234...ABCD)
export const formatAddress = (address: string): string => {
  if (!address) return '';
  return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
};

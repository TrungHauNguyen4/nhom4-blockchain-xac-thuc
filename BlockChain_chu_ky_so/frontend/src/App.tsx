import { useState, useRef } from 'react';
import { ShieldCheck, FileSignature, CheckCircle2, AlertCircle, Copy, Save, Search, UploadCloud, File as FileIcon, X } from 'lucide-react';
import { ethers } from 'ethers';
import './App.css';

// Hàm băm file tại máy client (Bảo mật: Không gửi file lên server)
const hashFileContent = async (file: File): Promise<string> => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      if (e.target?.result) {
        const buffer = e.target.result as ArrayBuffer;
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

const hashTextContent = (text: string): string => {
  return ethers.keccak256(ethers.toUtf8Bytes(text));
};

function App() {
  // Chế độ nhập liệu
  const [signMode, setSignMode] = useState<'text' | 'file'>('text');
  const [textToSign, setTextToSign] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Kết quả
  const [dataHash, setDataHash] = useState('');
  const [error, setError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitSuccess, setSubmitSuccess] = useState('');

  // Trạng thái Verify
  const [verifyHash, setVerifyHash] = useState('');
  const [isVerifying, setIsVerifying] = useState(false);
  const [verifyResult, setVerifyResult] = useState<{ signer: string; timestamp: number } | null>(null);
  const [verifyError, setVerifyError] = useState('');
  const verifyFileInputRef = useRef<HTMLInputElement>(null);

  const handleVerifyFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      const file = e.target.files[0];
      try {
        const hash = await hashFileContent(file);
        setVerifyHash(hash);
        handleVerifyWithHash(hash);
      } catch (err: any) {
        setVerifyError('Lỗi đọc file: ' + err.message);
      }
      if (verifyFileInputRef.current) verifyFileInputRef.current.value = '';
    }
  };

  const handleVerifyWithHash = async (hashToVerify: string) => {
    if (!hashToVerify.trim()) {
      setVerifyError('Vui lòng nhập Mã băm (Data Hash) cần kiểm tra');
      return;
    }
    
    setIsVerifying(true);
    setVerifyError('');
    setVerifyResult(null);

    try {
      const response = await fetch(`http://localhost:3000/api/v1/verify/${hashToVerify}`);
      const resData = await response.json();

      if (!response.ok) {
        throw new Error(resData.message || resData.error || 'Có lỗi xảy ra khi tra cứu');
      }

      setVerifyResult(resData.data);
    } catch (err: any) {
      setVerifyError('Lỗi tra cứu: ' + (err.message || err));
    } finally {
      setIsVerifying(false);
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      setSelectedFile(e.target.files[0]);
      setDataHash('');
      setSubmitSuccess('');
    }
  };

  const clearFile = () => {
    setSelectedFile(null);
    setDataHash('');
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  // Nút bấm: Tính Hash và Gọi API Backend
  const handleSubmit = async () => {
    setError('');
    setSubmitSuccess('');
    setDataHash('');
    
    try {
      let hash = '';
      if (signMode === 'text') {
        if (!textToSign.trim()) throw new Error('Vui lòng nhập nội dung!');
        hash = hashTextContent(textToSign);
      } else {
        if (!selectedFile) throw new Error('Vui lòng chọn một file!');
        hash = await hashFileContent(selectedFile);
      }

      setDataHash(hash);
      setIsSubmitting(true);

      // Xác định tên file
      const fileNameToSave = signMode === 'file' ? selectedFile?.name : 'Văn bản thuần túy';

      // Gọi API đến Backend Node.js
      const response = await fetch('http://localhost:3000/api/v1/notarize', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': 'YOUR_SECRET_B2B_KEY_123'
        },
        body: JSON.stringify({ 
          dataHash: hash,
          fileName: fileNameToSave 
        })
      });

      const resData = await response.json();

      if (!response.ok) {
        throw new Error(resData.error || 'Có lỗi xảy ra từ Server');
      }

      setSubmitSuccess(`Thành công! Mã giao dịch Blockchain: ${resData.transactionHash} (Block: ${resData.blockNumber})`);
    } catch (err: any) {
      setError(err.message || 'Lỗi không xác định');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleVerify = () => {
    handleVerifyWithHash(verifyHash);
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  return (
    <div className="app-container">
      <header className="header">
        <div className="logo-container">
          <ShieldCheck className="logo-icon" size={32} />
          <h1 className="logo-text">Enterprise e-Notary</h1>
        </div>
        
        <div>
          {/* Đã loại bỏ hoàn toàn nút Kết nối MetaMask ở đây */}
          <div className="badge badge-success" style={{ padding: '0.5rem 1rem' }}>
            <span className="font-mono">Chế độ Ẩn danh (B2B)</span>
          </div>
        </div>
      </header>

      {error && (
        <div className="badge badge-danger mb-4" style={{ display: 'flex', gap: '0.5rem', padding: '0.75rem', borderRadius: '0.5rem', width: '100%' }}>
          <AlertCircle size={18} />
          <span>{error}</span>
        </div>
      )}

      {submitSuccess && (
        <div className="badge badge-success mb-4" style={{ display: 'flex', gap: '0.5rem', padding: '0.75rem', borderRadius: '0.5rem', width: '100%', flexDirection: 'column' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <CheckCircle2 size={18} />
            <span style={{ fontWeight: 'bold' }}>Chứng chỉ đã được niêm phong an toàn!</span>
          </div>
          <span className="text-sm font-mono mt-1" style={{ opacity: 0.9 }}>{submitSuccess}</span>
        </div>
      )}

      <main className="grid-2">
        {/* Cột trái: Form Ký & Gửi Blockchain */}
        <section>
          <div className="glass-panel mb-4">
            <h2 className="mb-2" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <FileSignature size={24} color="var(--primary)" />
              1. Tải lên Dữ liệu cần Công chứng
            </h2>
            <p className="text-muted mb-4 text-sm">
              Hệ thống sẽ chỉ trích xuất Mã băm (Data Hash) của tài liệu và gửi lên máy chủ Công chứng. <b>File của bạn không bao giờ rời khỏi máy tính</b>.
            </p>

            <div style={{ display: 'flex', gap: '1rem', marginBottom: '1.5rem' }}>
              <button 
                className={`btn ${signMode === 'text' ? 'btn-primary' : 'btn-outline'}`}
                style={{ flex: 1 }}
                onClick={() => { setSignMode('text'); setDataHash(''); setSubmitSuccess(''); }}
              >
                Nhập Văn Bản
              </button>
              <button 
                className={`btn ${signMode === 'file' ? 'btn-primary' : 'btn-outline'}`}
                style={{ flex: 1 }}
                onClick={() => { setSignMode('file'); setDataHash(''); setSubmitSuccess(''); }}
              >
                Tải lên File PDF
              </button>
            </div>

            {signMode === 'text' && (
              <div className="form-group">
                <label className="form-label">Nội dung tài liệu</label>
                <textarea 
                  className="form-textarea" 
                  placeholder="Ví dụ: Hợp đồng cho thuê nhà ngày 29/07..."
                  value={textToSign}
                  onChange={(e) => setTextToSign(e.target.value)}
                ></textarea>
              </div>
            )}

            {signMode === 'file' && (
              <div className="form-group">
                <label className="form-label">Chọn File (PDF/Doc/Ảnh)</label>
                {!selectedFile ? (
                  <div 
                    onClick={() => fileInputRef.current?.click()}
                    style={{ 
                      border: '2px dashed var(--glass-border)', borderRadius: '0.5rem', padding: '2rem', textAlign: 'center', cursor: 'pointer', background: 'rgba(15, 23, 42, 0.4)'
                    }}
                  >
                    <UploadCloud size={48} color="var(--primary)" style={{ margin: '0 auto', opacity: 0.8 }} />
                    <p className="mt-4 text-sm text-muted">Bấm để chọn file cần đóng dấu thời gian</p>
                    <input type="file" ref={fileInputRef} onChange={handleFileChange} style={{ display: 'none' }} />
                  </div>
                ) : (
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', background: 'rgba(56, 189, 248, 0.1)', border: '1px solid var(--primary)', padding: '1rem', borderRadius: '0.5rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                      <FileIcon size={24} color="var(--primary)" />
                      <div>
                        <div className="text-sm font-bold word-break" style={{ color: 'var(--text-main)' }}>{selectedFile.name}</div>
                        <div className="text-sm text-muted">{(selectedFile.size / 1024 / 1024).toFixed(2)} MB</div>
                      </div>
                    </div>
                    <button className="btn-outline" style={{ padding: '0.25rem', border: 'none', color: 'var(--danger)' }} onClick={clearFile}>
                      <X size={20} />
                    </button>
                  </div>
                )}
              </div>
            )}

            {dataHash && (
              <div className="p-4 mb-4" style={{ background: 'rgba(0,0,0,0.2)', borderRadius: '0.5rem', border: '1px solid var(--glass-border)' }}>
                <div className="form-group mb-0">
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <label className="form-label mb-0">Mã Băm Tài Liệu (Hash)</label>
                    <button className="btn-outline" style={{ padding: '0.1rem 0.4rem', fontSize: '0.7rem', border: 'none' }} onClick={() => copyToClipboard(dataHash)}>
                      <Copy size={12} /> Copy
                    </button>
                  </div>
                  <div className="font-mono word-break text-sm mt-1" style={{ color: 'var(--primary)', fontSize: '0.85rem' }}>
                    {dataHash}
                  </div>
                </div>
              </div>
            )}

            <button 
              className="btn btn-primary" 
              style={{ width: '100%', marginTop: '1rem' }}
              onClick={handleSubmit}
              disabled={isSubmitting}
            >
              <Save size={18} />
              {isSubmitting ? 'Hệ thống đang xác thực...' : 'Niêm phong vĩnh viễn'}
            </button>
          </div>
        </section>

        {/* Cột phải: Form Xác minh (Verify) */}
        <section>
          <div className="glass-panel" style={{ height: '100%' }}>
            <h2 className="mb-2" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <Search size={24} color="var(--success)" />
              2. Tra cứu Chứng nhận
            </h2>
            <p className="text-muted mb-4 text-sm">
              Trang tra cứu độc lập. Dán mã băm (Hash) của tài liệu vào đây để đối chiếu với sổ cái Blockchain.
            </p>

            {verifyError && (
              <div className="badge badge-danger mb-4" style={{ display: 'flex', gap: '0.5rem', padding: '0.75rem', borderRadius: '0.5rem', width: '100%' }}>
                <AlertCircle size={18} />
                <span>{verifyError}</span>
              </div>
            )}

            <div className="form-group">
              <label className="form-label">Data Hash (0x...)</label>
              <div style={{ display: 'flex', gap: '0.5rem' }}>
                <input 
                  type="text" 
                  className="form-input font-mono text-sm" 
                  placeholder="Nhập Mã Băm..."
                  value={verifyHash}
                  onChange={(e) => setVerifyHash(e.target.value)}
                  style={{ flex: 1 }}
                />
                <button 
                  className="btn btn-outline" 
                  style={{ padding: '0.5rem 1rem', whiteSpace: 'nowrap' }}
                  onClick={() => verifyFileInputRef.current?.click()}
                  disabled={isVerifying}
                >
                  <UploadCloud size={18} style={{ marginRight: '0.5rem', display: 'inline' }} />
                  Tải File
                </button>
                <input 
                  type="file" 
                  ref={verifyFileInputRef} 
                  onChange={handleVerifyFileChange} 
                  style={{ display: 'none' }} 
                />
              </div>
            </div>

            <button 
              className="btn btn-outline" 
              style={{ width: '100%', borderColor: 'var(--success)', color: 'var(--success)' }}
              onClick={handleVerify}
              disabled={isVerifying}
            >
              {isVerifying ? 'Đang truy vấn sổ cái...' : 'Kiểm tra Bằng chứng'}
            </button>

            {verifyResult && (
              <div className="mt-4 p-4 result-box" style={{ borderLeft: '4px solid var(--success)', background: 'rgba(34, 197, 94, 0.05)' }}>
                <h4 className="mb-2 text-success" style={{ color: 'var(--success)' }}>✔ Tồn tại trên Blockchain</h4>
                
                <div className="mb-2">
                  <span className="text-muted text-sm block">Được niêm phong bởi Hệ thống (Ví Công chứng):</span>
                  <div className="font-mono word-break" style={{ color: 'var(--text-main)', fontSize: '0.85rem' }}>
                    {verifyResult.signer}
                  </div>
                </div>

                <div>
                  <span className="text-muted text-sm block">Mốc thời gian (Timestamp):</span>
                  <div className="font-mono" style={{ fontSize: '0.9rem' }}>
                    {new Date(verifyResult.timestamp * 1000).toLocaleString('vi-VN')}
                  </div>
                </div>
              </div>
            )}

          </div>
        </section>
      </main>
    </div>
  );
}

export default App;

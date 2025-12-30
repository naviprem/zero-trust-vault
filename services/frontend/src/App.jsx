import React, { useState, useEffect } from 'react';
import { Shield, FileText, Lock, Activity, Server, User, Terminal, LogOut } from 'lucide-react';

function App() {
    const [token, setToken] = useState(localStorage.getItem('vault_token'));
    const [user, setUser] = useState(null);
    const [documents, setDocuments] = useState([]);
    const [debug, setDebug] = useState(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [selectedUser, setSelectedUser] = useState('alice');

    useEffect(() => {
        if (token) {
            fetchData();
            try {
                const payload = JSON.parse(atob(token.split('.')[1]));
                setUser({
                    name: payload.preferred_username,
                    roles: payload.realm_access?.roles || []
                });
            } catch (e) {
                console.error("Failed to decode token", e);
            }
        }
    }, [token]);

    const handleTestLogin = async (username) => {
        setLoading(true);
        setError(null);

        try {
            const response = await fetch('/realms/zero-trust/protocol/openid-connect/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    grant_type: 'password',
                    client_id: 'frontend-app',
                    username: username,
                    password: username === 'alice' ? 'alice123' : 'bob123'
                })
            });

            if (!response.ok) {
                throw new Error('Failed to get token from Keycloak');
            }

            const data = await response.json();
            setToken(data.access_token);
            localStorage.setItem('vault_token', data.access_token);
        } catch (err) {
            setError(`Login failed: ${err.message}`);
        } finally {
            setLoading(false);
        }
    };

    const handleLogout = () => {
        setToken(null);
        setUser(null);
        setDocuments([]);
        setDebug(null);
        localStorage.removeItem('vault_token');
    };

    const fetchData = async () => {
        if (!token) return;
        setLoading(true);
        try {
            const headers = { 'Authorization': `Bearer ${token}` };

            const docRes = await fetch('/api/documents', { headers });
            if (!docRes.ok) throw new Error(docRes.status === 403 ? 'Access Denied: OPA Policy Violation' : 'Backend Unreachable');
            const docData = await docRes.json();
            setDocuments(docData.documents || []);

            const debugRes = await fetch('/api/spiffe-debug', { headers });
            const debugData = await debugRes.json();
            setDebug(debugData);
            setError(null);
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    if (!token) {
        return (
            <div className="dashboard" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '100vh' }}>
                <div className="glass-card" style={{ maxWidth: '400px', width: '100%', padding: '2rem' }}>
                    <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
                        <Shield size={48} color="#60a5fa" style={{ marginBottom: '1rem' }} />
                        <h1 style={{ fontSize: '1.5rem', marginBottom: '0.5rem' }}>Zero Trust Vault</h1>
                        <p style={{ color: '#94a3b8' }}>Secure Identity Gateway - Test Mode</p>
                    </div>

                    <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                        <div>
                            <label style={{ display: 'block', marginBottom: '0.5rem', color: '#cbd5e1' }}>Select Test User</label>
                            <select
                                value={selectedUser}
                                onChange={(e) => setSelectedUser(e.target.value)}
                                style={{
                                    width: '100%',
                                    padding: '0.75rem',
                                    background: 'rgba(30, 41, 59, 0.5)',
                                    border: '1px solid rgba(148, 163, 184, 0.2)',
                                    borderRadius: '0.5rem',
                                    color: 'white'
                                }}
                            >
                                <option value="alice">Alice (Admin - Full Access)</option>
                                <option value="bob">Bob (User - Limited Access)</option>
                            </select>
                        </div>

                        <button
                            onClick={() => handleTestLogin(selectedUser)}
                            disabled={loading}
                            style={{
                                padding: '0.75rem',
                                background: 'linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%)',
                                border: 'none',
                                borderRadius: '0.5rem',
                                color: 'white',
                                fontWeight: '600',
                                cursor: loading ? 'not-allowed' : 'pointer',
                                opacity: loading ? 0.5 : 1
                            }}
                        >
                            {loading ? 'Logging in...' : `Login as ${selectedUser.charAt(0).toUpperCase() + selectedUser.slice(1)}`}
                        </button>

                        {error && (
                            <div style={{
                                padding: '0.75rem',
                                background: 'rgba(239, 68, 68, 0.1)',
                                border: '1px solid rgba(239, 68, 68, 0.3)',
                                borderRadius: '0.5rem',
                                color: '#fca5a5'
                            }}>
                                {error}
                            </div>
                        )}

                        <div style={{ marginTop: '1rem', padding: '1rem', background: 'rgba(59, 130, 246, 0.1)', borderRadius: '0.5rem', fontSize: '0.875rem', color: '#93c5fd' }}>
                            <p style={{ marginBottom: '0.5rem' }}><strong>Test Credentials:</strong></p>
                            <p>• Alice: Full document access</p>
                            <p>• Bob: Limited to own documents</p>
                        </div>
                    </div>
                </div>
            </div>
        );
    }

    return (
        <div className="dashboard">
            <header className="glass-card" style={{ marginBottom: '2rem', padding: '1.5rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
                    <Shield size={32} color="#60a5fa" />
                    <div>
                        <h1 style={{ fontSize: '1.25rem', marginBottom: '0.25rem' }}>Zero Trust Vault</h1>
                        <p style={{ fontSize: '0.875rem', color: '#94a3b8' }}>Logged in as: <strong>{user?.name}</strong></p>
                    </div>
                </div>
                <button onClick={handleLogout} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', padding: '0.5rem 1rem', background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.3)', borderRadius: '0.5rem', color: '#fca5a5', cursor: 'pointer' }}>
                    <LogOut size={16} />
                    Logout
                </button>
            </header>

            {error && (
                <div className="glass-card" style={{ marginBottom: '2rem', padding: '1rem', background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.3)' }}>
                    <p style={{ color: '#fca5a5' }}>{error}</p>
                </div>
            )}

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '1.5rem', marginBottom: '2rem' }}>
                <div className="glass-card" style={{ padding: '1.5rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem' }}>
                        <FileText size={24} color="#60a5fa" />
                        <h2 style={{ fontSize: '1.125rem' }}>Documents</h2>
                    </div>
                    <p style={{ fontSize: '2rem', fontWeight: '700', color: '#60a5fa' }}>{documents.length}</p>
                    <p style={{ fontSize: '0.875rem', color: '#94a3b8' }}>Accessible documents</p>
                </div>

                <div className="glass-card" style={{ padding: '1.5rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem' }}>
                        <User size={24} color="#34d399" />
                        <h2 style={{ fontSize: '1.125rem' }}>Identity</h2>
                    </div>
                    <p style={{ fontSize: '1.25rem', fontWeight: '600', color: '#34d399' }}>{user?.name}</p>
                    <p style={{ fontSize: '0.875rem', color: '#94a3b8' }}>Roles: {user?.roles.join(', ')}</p>
                </div>

                <div className="glass-card" style={{ padding: '1.5rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem' }}>
                        <Activity size={24} color="#f59e0b" />
                        <h2 style={{ fontSize: '1.125rem' }}>Status</h2>
                    </div>
                    <p style={{ fontSize: '1.25rem', fontWeight: '600', color: '#f59e0b' }}>{loading ? 'Loading...' : 'Active'}</p>
                    <p style={{ fontSize: '0.875rem', color: '#94a3b8' }}>System operational</p>
                </div>
            </div>

            <div className="glass-card" style={{ marginBottom: '2rem', padding: '1.5rem' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem' }}>
                    <FileText size={24} color="#60a5fa" />
                    <h2 style={{ fontSize: '1.125rem' }}>Document List</h2>
                </div>
                {documents.length === 0 ? (
                    <p style={{ color: '#94a3b8', textAlign: 'center', padding: '2rem' }}>No documents available</p>
                ) : (
                    <div style={{ display: 'grid', gap: '0.75rem' }}>
                        {documents.map((doc, idx) => (
                            <div key={idx} style={{ padding: '1rem', background: 'rgba(30, 41, 59, 0.5)', borderRadius: '0.5rem', border: '1px solid rgba(148, 163, 184, 0.2)' }}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                    <div>
                                        <span style={{ padding: '1rem', fontWeight: '600', marginBottom: '0.25rem' }}>{doc.name}</span>
                                        <span style={{ padding: '1rem', fontSize: '0.875rem', color: '#94a3b8' }}>Id: {doc.id}</span>
                                        <span style={{ padding: '1rem', fontSize: '0.875rem', color: '#94a3b8' }}>Security Level: {doc.securityLevel}</span>
                                    </div>
                                    <Lock size={16} color="#94a3b8" />
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </div>

            {debug && (
                <div className="glass-card" style={{ padding: '1.5rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem' }}>
                        <Terminal size={24} color="#a78bfa" />
                        <h2 style={{ fontSize: '1.125rem' }}>SPIFFE Debug Info</h2>
                    </div>
                    <pre style={{ background: 'rgba(0, 0, 0, 0.3)', padding: '1rem', borderRadius: '0.5rem', overflow: 'auto', fontSize: '0.875rem', color: '#cbd5e1' }}>
                        {JSON.stringify(debug, null, 2)}
                    </pre>
                </div>
            )}
        </div>
    );
}

export default App;

"use client";

import { useEffect, useState } from "react";
import { getApiBase } from "@/lib/api";

export default function SettingsPage() {
  const [endpoint, setEndpoint] = useState("");

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setEndpoint(getApiBase());
  }, []);

  return (
    <div className="settings-view">
      <h2>Settings</h2>
      <div className="settings-card">
        <div className="setting-item">
          <div className="setting-label">
            <h4>API Endpoint</h4>
            <p>The backend API URL</p>
          </div>
          <div className="setting-value">
            <code>{endpoint}</code>
          </div>
        </div>
        <div className="setting-item">
          <div className="setting-label">
            <h4>Application Version</h4>
            <p>Current dashboard version</p>
          </div>
          <div className="setting-value">
            <span>1.0.0</span>
          </div>
        </div>
      </div>
    </div>
  );
}

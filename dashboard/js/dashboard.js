/**
 * ResQ AI Responder Dashboard
 * Fetches incidents from backend and displays them with map and timeline.
 */

const API_BASE = 'http://localhost:8000';
let map = null;
let markers = [];
let selectedIncident = null;

const Dashboard = {
    init() {
        this.initMap();
        this.refresh();
        // Auto-refresh every 10 seconds
        setInterval(() => this.refresh(), 10000);
    },

    initMap() {
        map = L.map('map').setView([20.5937, 78.9629], 5); // Center on India
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '&copy; OpenStreetMap contributors',
            maxZoom: 18,
        }).addTo(map);

        // Force map to recalculate size
        setTimeout(() => map.invalidateSize(), 100);
    },

    async refresh() {
        try {
            const response = await fetch(`${API_BASE}/incidents`);
            if (!response.ok) throw new Error('Failed to fetch');
            const data = await response.json();
            this.updateConnectionStatus(true);
            this._allIncidents = data.incidents || [];
            this.renderIncidents(this._allIncidents);
            this.updateSummary(this._allIncidents);
        } catch (err) {
            console.error('Refresh failed:', err);
            this.updateConnectionStatus(false);
            // Load demo data if backend is unavailable
            this.loadDemoData();
        }
    },

    updateConnectionStatus(connected) {
        const dot = document.getElementById('connection-status');
        const text = document.getElementById('status-text');
        if (connected) {
            dot.className = 'status-dot online';
            text.textContent = 'Connected';
        } else {
            dot.className = 'status-dot offline';
            text.textContent = 'Demo Mode';
        }
    },

    updateSummary(incidents) {
        let critical = 0, high = 0, medium = 0, low = 0;
        incidents.forEach(inc => {
            switch (inc.severity) {
                case 'CRITICAL': critical++; break;
                case 'HIGH': high++; break;
                case 'MEDIUM': medium++; break;
                case 'LOW': low++; break;
            }
        });
        document.getElementById('critical-count').textContent = critical;
        document.getElementById('high-count').textContent = high;
        document.getElementById('medium-count').textContent = medium;
        document.getElementById('low-count').textContent = low;
        document.getElementById('total-count').textContent = incidents.length;
    },

    renderIncidents(incidents) {
        const list = document.getElementById('incident-list');
        if (!incidents.length) {
            list.innerHTML = '<div class="empty-state">No active emergencies</div>';
            return;
        }

        // Clear old markers
        markers.forEach(m => map.removeLayer(m));
        markers = [];

        list.innerHTML = incidents.map(inc => {
            const time = new Date(inc.time).toLocaleTimeString();
            return `
                <div class="incident-card" onclick="Dashboard.selectIncident('${inc.incident_id}')" data-id="${inc.incident_id}">
                    <div class="incident-card-header">
                        <span class="incident-id">#${inc.incident_id}</span>
                        <span class="severity-badge severity-${inc.severity}">${inc.severity}</span>
                    </div>
                    <div class="incident-meta">
                        <span>⏱ ${time}</span>
                        <span class="incident-score">Score: ${inc.emergency_score}</span>
                        <span>🚗 ${inc.speed_kmh.toFixed(1)} km/h</span>
                    </div>
                </div>
            `;
        }).join('');

        // Add map markers
        incidents.forEach(inc => {
            if (inc.location && inc.location.latitude && inc.location.longitude) {
                const color = this.getSeverityColor(inc.severity);
                const marker = L.circleMarker(
                    [inc.location.latitude, inc.location.longitude],
                    {
                        radius: 10,
                        fillColor: color,
                        color: '#fff',
                        weight: 2,
                        fillOpacity: 0.8,
                    }
                ).addTo(map);
                marker.bindPopup(`
                    <b>#${inc.incident_id}</b><br>
                    Severity: ${inc.severity}<br>
                    Score: ${inc.emergency_score}<br>
                    Speed: ${inc.speed_kmh.toFixed(1)} km/h
                `);
                markers.push(marker);
            }
        });

        // Fit bounds if we have markers
        if (markers.length > 0) {
            const group = L.featureGroup(markers);
            map.fitBounds(group.getBounds().pad(0.3));
        }
    },

    selectIncident(incidentId) {
        // Highlight card
        document.querySelectorAll('.incident-card').forEach(c => c.classList.remove('selected'));
        const card = document.querySelector(`[data-id="${incidentId}"]`);
        if (card) card.classList.add('selected');

        // Find incident data
        const incident = this._allIncidents.find(i => i.incident_id === incidentId);
        if (!incident) return;

        selectedIncident = incident;
        this.renderDetail(incident);
    },

    renderDetail(inc) {
        const detail = document.getElementById('incident-detail');
        const time = new Date(inc.time).toLocaleString();

        detail.innerHTML = `
            <div class="detail-grid">
                <div class="detail-item">
                    <label>Incident ID</label>
                    <div class="value blue">#${inc.incident_id}</div>
                </div>
                <div class="detail-item">
                    <label>Severity</label>
                    <div class="value ${this.getSeverityColorClass(inc.severity)}">${inc.severity}</div>
                </div>
                <div class="detail-item">
                    <label>Emergency Score</label>
                    <div class="value orange">${inc.emergency_score} / 100</div>
                </div>
                <div class="detail-item">
                    <label>Status</label>
                    <div class="value">${inc.status}</div>
                </div>
                <div class="detail-item">
                    <label>Speed</label>
                    <div class="value">${inc.speed_kmh.toFixed(1)} km/h</div>
                </div>
                <div class="detail-item">
                    <label>Impact</label>
                    <div class="value">${inc.impact_magnitude.toFixed(1)} m/s²</div>
                </div>
                <div class="detail-item">
                    <label>Location</label>
                    <div class="value" style="font-size:14px">
                        ${inc.location.latitude.toFixed(5)}, ${inc.location.longitude.toFixed(5)}
                    </div>
                </div>
                <div class="detail-item">
                    <label>Time</label>
                    <div class="value" style="font-size:14px">${time}</div>
                </div>
            </div>
        `;

        // Render timeline
        if (inc.timeline && inc.timeline.length > 0) {
            const timelineSection = document.getElementById('timeline-section');
            const timeline = document.getElementById('timeline');
            timelineSection.style.display = 'block';

            timeline.innerHTML = inc.timeline.map(entry => {
                const severity = entry.score > 70 ? 'critical' :
                    entry.score > 50 ? 'high' :
                    entry.score > 30 ? 'medium' : 'low';
                return `
                    <div class="timeline-item ${severity}">
                        <div class="timeline-time">${entry.timestamp}</div>
                        <div class="timeline-desc">${entry.description}</div>
                    </div>
                `;
            }).join('');
        }

        // Pan map to location
        if (inc.location && inc.location.latitude && inc.location.longitude) {
            map.setView([inc.location.latitude, inc.location.longitude], 14);
        }
    },

    getSeverityColor(severity) {
        switch (severity) {
            case 'CRITICAL': return '#ef4444';
            case 'HIGH': return '#f59e0b';
            case 'MEDIUM': return '#eab308';
            case 'LOW': return '#22c55e';
            default: return '#3b82f6';
        }
    },

    getSeverityColorClass(severity) {
        switch (severity) {
            case 'CRITICAL': return 'red';
            case 'HIGH': return 'orange';
            case 'MEDIUM': return 'orange';
            case 'LOW': return 'green';
            default: return 'blue';
        }
    },

    loadDemoData() {
        const demoIncidents = [
            {
                incident_id: 'DEMO001',
                location: { latitude: 28.6139, longitude: 77.2090 },
                time: new Date(Date.now() - 300000).toISOString(),
                speed_kmh: 45.0,
                impact_magnitude: 52.3,
                emergency_score: 85,
                severity: 'CRITICAL',
                status: 'CONFIRMED',
                timeline: [
                    { timestamp: '10:42:00', description: 'Normal movement', activity_type: 'walking', score: 5 },
                    { timestamp: '10:43:00', description: 'Movement detected', activity_type: 'normal', score: 10 },
                    { timestamp: '10:44:00', description: 'Speed increased', activity_type: 'driving', score: 25 },
                    { timestamp: '10:44:08', description: 'HIGH IMPACT detected', activity_type: 'emergency', score: 85 },
                    { timestamp: '10:44:12', description: 'Sudden stop', activity_type: 'emergency', score: 90 },
                    { timestamp: '10:44:40', description: 'No movement (possible unconsciousness)', activity_type: 'emergency', score: 95 },
                ],
            },
            {
                incident_id: 'DEMO002',
                location: { latitude: 19.0760, longitude: 72.8777 },
                time: new Date(Date.now() - 600000).toISOString(),
                speed_kmh: 60.0,
                impact_magnitude: 38.1,
                emergency_score: 72,
                severity: 'HIGH',
                status: 'CONFIRMED',
                timeline: [
                    { timestamp: '09:15:00', description: 'Driving at normal speed', activity_type: 'driving', score: 10 },
                    { timestamp: '09:16:30', description: 'Speed increased', activity_type: 'driving', score: 20 },
                    { timestamp: '09:17:00', description: 'High impact', activity_type: 'emergency', score: 72 },
                    { timestamp: '09:17:10', description: 'Sudden deceleration', activity_type: 'emergency', score: 78 },
                ],
            },
            {
                incident_id: 'DEMO003',
                location: { latitude: 12.9716, longitude: 77.5946 },
                time: new Date(Date.now() - 900000).toISOString(),
                speed_kmh: 25.0,
                impact_magnitude: 22.0,
                emergency_score: 45,
                severity: 'MEDIUM',
                status: 'DETECTED',
                timeline: [
                    { timestamp: '14:30:00', description: 'Cycling detected', activity_type: 'cycling', score: 8 },
                    { timestamp: '14:31:00', description: 'Unusual movement', activity_type: 'suspicious', score: 45 },
                ],
            },
        ];

        this._allIncidents = demoIncidents;
        this.renderIncidents(demoIncidents);
        this.updateSummary(demoIncidents);
    },

    _allIncidents: [],
};

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => Dashboard.init());

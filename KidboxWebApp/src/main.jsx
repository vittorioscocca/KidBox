import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import { captureInviteFromLocation } from './services/pendingInvite'

// Prima del render: il segreto dell'invito sta nel frammento dell'URL e va
// messo da parte prima che il login social ricarichi la pagina.
captureInviteFromLocation()

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

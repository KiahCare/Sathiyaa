/**
 * Signing a provider up from the office.
 *
 * Most of Sathiyaa's carers and every agency are taken on in person rather than
 * through the app. Until this existed, the only way to get either into the
 * system was to borrow the provider's handset and drive the provider app's
 * registration form on it — and when that was done on an office phone instead,
 * the account bound itself to the office phone and the provider could never
 * sign in from their own.
 *
 * THE STEPS ARE THE APP'S STEPS, IN THE APP'S ORDER
 *
 * Five of them, named the same way, asking the same questions: You / Work / Pay
 * / Papers / PIN for a carer, and Organisation / Office / Rates / Registration /
 * PIN for an agency. That is not decoration. Somebody in the office reads a
 * provider's answers off a paper form or over the phone in whatever order the
 * app would have asked for them, and a console that asked for the same things in
 * a different order is how a field gets skipped.
 *
 * WHO CHECKS WHAT
 *
 * The server owns the rules. It answers 422 with `error.fields` keyed by the
 * same names this form uses for its inputs, and `applyServerFields` below puts
 * each message next to the box it is about and jumps to the earliest step that
 * has one. The checks in `localGaps` are only about whether a step is complete
 * enough to move on from — presence, and the couple of formats worth catching
 * before a round trip. Writing the full rule set twice would mean two sets to
 * keep in step, and the copy in the browser is the one that can be skipped.
 *
 * WHY THE MAP IS NOT OPTIONAL
 *
 * The booking search filters candidates with `HAVING distance_km <= ?`, and
 * distance_km is NULL for a provider whose address has no coordinates — so NULL
 * <= 35 is not true and that provider is returned by no search at all, while
 * looking entirely healthy in this console. The app gets coordinates from the
 * handset's GPS. Here they come from the geocoder or from dragging the pin, and
 * the form will not submit without them.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

import type {
  ApprovalStatus, DayOfWeek, Gender, NewProviderPayload, NewProviderResult, ServiceType,
} from '../../types';
import { DAY_LABELS, LANGUAGES, SERVICE_TYPE_LABELS } from '../../types';
import { createProvider, geocodeAddress, uploadProviderDocument } from '../../api/services';
import { ApiRequestError } from '../../api/client';
import { InlineBanner, Modal } from '../../components/ui';

type Kind = 'freelancer' | 'organization';

const DAYS: DayOfWeek[] = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const SERVICES: ServiceType[] = ['companion', 'medical_companion', 'nurse', 'physiotherapy'];

/** The two services a medical certificate is required for, as the server has it. */
const CLINICAL: ServiceType[] = ['nurse', 'physiotherapy'];

/** Where Sathiyaa operates, so the map opens somewhere useful. */
const CITY_CENTRE: L.LatLngTuple = [23.0225, 72.5714];

const STEP_TITLES: Record<Kind, string[]> = {
  freelancer: ['You', 'Work', 'Pay', 'Papers', 'PIN'],
  organization: ['Organisation', 'Office', 'Rates', 'Registration', 'PIN'],
};

/**
 * Which step each field the server can complain about belongs to.
 *
 * Keyed by the names `adminController.createProvider` uses in `error.fields`.
 * A name missing from here is shown as a banner at the top rather than silently
 * dropped, which is what happens if the two sides ever drift.
 */
const FIELD_STEP: Record<string, number> = {
  providerKind: 0, name: 0, contactPerson: 0, gender: 0, dob: 0, mobile: 0, email: 0,
  address: 1, location: 1, workHours: 1, expertise: 1,
  hourlyRate: 2,
  aadharDocUrl: 3, policeVerificationUrl: 3, policeVerificationDates: 3,
  medicalCertificateUrl: 3, medicalCertificateDates: 3, gstNumber: 3, orgRegistrationUrl: 3,
  pin: 4,
};

type DocCategory = Parameters<typeof uploadProviderDocument>[1];

interface DocState {
  url: string | null;
  fileName: string | null;
  validFrom: string;
  validTo: string;
  uploading: boolean;
  error: string | null;
}

const emptyDoc = (): DocState => ({
  url: null, fileName: null, validFrom: '', validTo: '', uploading: false, error: null,
});

/**
 * Six digits that the server will accept.
 *
 * `crypto.getRandomValues` rather than `Math.random`, and the same three
 * refusals the server applies, so "Generate" never produces something that is
 * then rejected.
 */
function generatePin(): string {
  for (;;) {
    const bytes = new Uint32Array(1);
    crypto.getRandomValues(bytes);
    const pin = String(bytes[0] % 1_000_000).padStart(6, '0');
    if (/^(\d)\1{5}$/.test(pin)) continue;
    if (pin === '123456' || pin === '654321') continue;
    return pin;
  }
}

// ---------------------------------------------------------------------
// Small pieces of the form
// ---------------------------------------------------------------------
//
// These three live at module scope, not inside the dialog, and that is load
// bearing. A component declared inside another component is a *different*
// component on every render, so React unmounts the old one and mounts a new one
// each time any state changes. For `Toggle` that is only wasteful. For
// `DocField` it was a bug you could watch happen: attaching one document
// re-rendered the dialog, which remounted every file input, which cleared the
// file somebody had just chosen in another one — and typing in a validity date
// lost focus after each character.

function Toggle({ on, onClick, children }: {
  on: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="btn btn-sm"
      style={{
        borderColor: on ? 'var(--color-primary)' : 'var(--color-border)',
        background: on ? 'var(--color-primary-light)' : 'var(--color-surface)',
        color: on ? 'var(--color-primary-dark)' : 'var(--color-text)',
        fontWeight: on ? 700 : 500,
      }}
    >
      {children}
    </button>
  );
}

function FieldError({ errors, name }: { errors: Record<string, string>; name: string }) {
  return errors[name] ? <div className="err-text">{errors[name]}</div> : null;
}

function DocField({
  label, hint, doc, category, fieldKey, dates, datesKey, errors, onPick, onDates, clearError,
}: {
  label: string;
  hint: string;
  doc: DocState;
  category: DocCategory;
  fieldKey: string;
  dates?: boolean;
  datesKey?: string;
  errors: Record<string, string>;
  onPick: (file: File | undefined, category: DocCategory, fieldKey: string) => void;
  onDates: (patch: Partial<Pick<DocState, 'validFrom' | 'validTo'>>) => void;
  clearError: (key: string) => void;
}) {
  return (
    <div style={{ marginBottom: 18 }}>
      <label className="field-label">{label}</label>
      <div className="field-hint" style={{ marginBottom: 6 }}>{hint}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp,image/heic,application/pdf"
          onChange={(ev) => onPick(ev.target.files?.[0], category, fieldKey)}
          style={{ fontSize: 13 }}
        />
        {doc.uploading && <span className="field-hint">Uploading…</span>}
        {doc.url && !doc.uploading && (
          <span className="badge badge-green">Attached{doc.fileName ? `: ${doc.fileName}` : ''}</span>
        )}
      </div>
      {doc.error && <div className="err-text">{doc.error}</div>}
      <FieldError errors={errors} name={fieldKey} />
      {dates && (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 10 }}>
          <div>
            <label className="field-label">Valid from</label>
            <input
              type="date"
              className={`input ${datesKey && errors[datesKey] ? 'err' : ''}`}
              value={doc.validFrom}
              onChange={(ev) => { onDates({ validFrom: ev.target.value }); if (datesKey) clearError(datesKey); }}
            />
          </div>
          <div>
            <label className="field-label">Valid to</label>
            <input
              type="date"
              className={`input ${datesKey && errors[datesKey] ? 'err' : ''}`}
              value={doc.validTo}
              onChange={(ev) => { onDates({ validTo: ev.target.value }); if (datesKey) clearError(datesKey); }}
            />
          </div>
        </div>
      )}
      {datesKey && <FieldError errors={errors} name={datesKey} />}
    </div>
  );
}

/**
 * What to show once the account exists — and the only time the PIN is readable.
 *
 * The PIN is never sent back by the server and is never written to the audit
 * log; this panel is showing the value that was typed into the form a moment
 * ago, held in memory for as long as the panel is open. Once it is closed the
 * only way back in is a reset, so the panel says so rather than letting somebody
 * discover it.
 */
export function ProviderCreatedPanel({ result, pin, onClose }: {
  result: NewProviderResult;
  pin: string;
  onClose: () => void;
}) {
  const p = result.provider;
  const [shown, setShown] = useState(false);
  return (
    // Not dismissable by clicking away either: this is the only time the PIN can
    // be read, and losing it to a stray click means a reset the provider has to
    // do themselves.
    <Modal onClose={onClose} width={520} dismissOnBackdrop={false}>
      <div style={{ padding: 24 }}>
        <h3 style={{ margin: '0 0 6px', fontSize: 17, fontWeight: 700 }}>{p.name} has been added</h3>
        <p style={{ margin: '0 0 18px', fontSize: 13.5, color: 'var(--color-text-muted)', lineHeight: 1.55 }}>
          {p.display_id} · {p.provider_kind === 'organization' ? 'Organisation' : 'Freelance carer'} ·{' '}
          {p.approval_status === 'approved' ? 'approved and visible in customer search' : `approval ${p.approval_status}`}
        </p>

        <div className="card" style={{ padding: 16, marginBottom: 16 }}>
          <div style={{ fontSize: 12, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.03em', color: 'var(--color-text-muted)' }}>
            Sign-in details to pass on
          </div>
          <div style={{ marginTop: 10, fontSize: 14 }}>
            <div>Mobile number: <strong>{p.mobile_number}</strong></div>
            <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', gap: 10 }}>
              <span>PIN:</span>
              <strong style={{ letterSpacing: '0.3em', fontSize: 16 }}>{shown ? pin : '••••••'}</strong>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShown(!shown)}>
                {shown ? 'Hide' : 'Show'}
              </button>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() => void navigator.clipboard?.writeText(pin)}
              >
                Copy
              </button>
            </div>
          </div>
          <div className="field-hint" style={{ marginTop: 10 }}>
            This is the last time the PIN can be read. It is stored hashed, so if it is lost the
            provider has to reset it from the app's “Forgot PIN” screen.
          </div>
        </div>

        {result.outstanding.length > 0 && (
          <div className="card" style={{ padding: 16, marginBottom: 16, borderColor: 'var(--color-warning)' }}>
            <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--color-warning)' }}>Still outstanding</div>
            <ul style={{ margin: '8px 0 0', paddingLeft: 18, fontSize: 13, lineHeight: 1.6 }}>
              {result.outstanding.map((o) => <li key={o}>{o}</li>)}
            </ul>
          </div>
        )}

        <p style={{ margin: '0 0 18px', fontSize: 13, color: 'var(--color-text-muted)', lineHeight: 1.55 }}>
          They can sign in on their own phone now. The first handset to sign in becomes the one the
          account is tied to; if they later change phone, use <strong>Release device</strong> on their
          row here.
        </p>

        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <button className="btn btn-primary" onClick={onClose}>Done</button>
        </div>
      </div>
    </Modal>
  );
}

export default function AddProviderDialog({ onClose, onCreated }: {
  onClose: () => void;
  onCreated: (result: NewProviderResult, pin: string) => void;
}) {
  const [step, setStep] = useState(0);
  const [kind, setKind] = useState<Kind>('freelancer');
  const isOrg = kind === 'organization';

  // ---- step 0: who this is ---------------------------------------------
  const [name, setName] = useState('');
  const [contactPerson, setContactPerson] = useState('');
  const [gender, setGender] = useState<Gender | ''>('female');
  const [dob, setDob] = useState('');
  const [mobile, setMobile] = useState('');
  const [email, setEmail] = useState('');

  // ---- step 1: where, when, what ---------------------------------------
  const [line1, setLine1] = useState('');
  const [line2, setLine2] = useState('');
  const [city, setCity] = useState('Ahmedabad');
  const [stateName, setStateName] = useState('Gujarat');
  const [pincode, setPincode] = useState('');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [locating, setLocating] = useState(false);
  const [locationNote, setLocationNote] = useState<string | null>(null);
  const [days, setDays] = useState<Set<DayOfWeek>>(new Set(['mon', 'tue', 'wed', 'thu', 'fri']));
  const [from, setFrom] = useState('09:00');
  const [to, setTo] = useState('18:00');
  const [differentHours, setDifferentHours] = useState(false);
  const [perDay, setPerDay] = useState<Record<string, { from: string; to: string }>>({});
  const [services, setServices] = useState<Set<ServiceType>>(new Set(['companion']));

  // ---- step 2: money and language --------------------------------------
  const [rate, setRate] = useState('');
  const [noFees, setNoFees] = useState(false);
  const [languages, setLanguages] = useState<Set<string>>(new Set(['English']));

  // ---- step 3: papers ---------------------------------------------------
  const [photo, setPhoto] = useState<DocState>(emptyDoc);
  const [aadhar, setAadhar] = useState<DocState>(emptyDoc);
  const [police, setPolice] = useState<DocState>(emptyDoc);
  const [medical, setMedical] = useState<DocState>(emptyDoc);
  const [orgCert, setOrgCert] = useState<DocState>(emptyDoc);
  const [gst, setGst] = useState('');

  // ---- step 4: how they sign in, and what we have decided --------------
  const [pin, setPin] = useState('');
  const [approvalStatus, setApprovalStatus] = useState<ApprovalStatus>('approved');
  const [feePaid, setFeePaid] = useState(false);
  const [allocateViaOrg, setAllocateViaOrg] = useState(true);

  const [errors, setErrors] = useState<Record<string, string>>({});
  const [banner, setBanner] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const clinical = useMemo(() => [...services].some((s) => CLINICAL.includes(s)), [services]);
  const titles = STEP_TITLES[kind];
  const lastStep = titles.length - 1;

  const clearError = (key: string) => setErrors((e) => {
    if (!(key in e)) return e;
    const next = { ...e };
    delete next[key];
    return next;
  });

  // -------------------------------------------------------------------
  // The map
  // -------------------------------------------------------------------
  //
  // Plain Leaflet and a draggable marker, matching how Tracking.tsx does it:
  // the React wrappers add a dependency and a lifecycle to reason about for a
  // map that has one pin on it.
  const mapHost = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markerRef = useRef<L.Marker | null>(null);

  useEffect(() => {
    if (step !== 1 || !mapHost.current || mapRef.current) return;
    const map = L.map(mapHost.current, { scrollWheelZoom: true, attributionControl: false })
      .setView(lat !== null && lng !== null ? [lat, lng] : CITY_CENTRE, lat !== null ? 15 : 12);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19 }).addTo(map);

    // Clicking anywhere drops the pin there, which is quicker than dragging
    // when the geocoder has put it in the wrong part of town.
    map.on('click', (e: L.LeafletMouseEvent) => setPin_(e.latlng.lat, e.latlng.lng));
    mapRef.current = map;

    if (lat !== null && lng !== null) placeMarker(lat, lng);
    // Leaflet measures its container on creation, and the modal animates in, so
    // the first measurement can be of a box that is not its final size.
    setTimeout(() => map.invalidateSize(), 60);

    return () => {
      map.remove();
      mapRef.current = null;
      markerRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step]);

  function placeMarker(latitude: number, longitude: number) {
    const map = mapRef.current;
    if (!map) return;
    if (!markerRef.current) {
      markerRef.current = L.marker([latitude, longitude], { draggable: true }).addTo(map);
      markerRef.current.on('dragend', () => {
        const p = markerRef.current!.getLatLng();
        setPin_(p.lat, p.lng, { keepView: true });
      });
    } else {
      markerRef.current.setLatLng([latitude, longitude]);
    }
  }

  function setPin_(latitude: number, longitude: number, opts?: { keepView?: boolean }) {
    setLat(Number(latitude.toFixed(7)));
    setLng(Number(longitude.toFixed(7)));
    clearError('location');
    placeMarker(latitude, longitude);
    if (!opts?.keepView) mapRef.current?.setView([latitude, longitude], 16);
    setLocationNote('Pin set. Drag it, or click the map, to adjust.');
  }

  async function findOnMap() {
    const q = [line1, line2, city, stateName, pincode].filter(Boolean).join(', ');
    if (q.trim().length < 3) {
      setErrors((e) => ({ ...e, address: 'Type the address first.' }));
      return;
    }
    setLocating(true);
    setLocationNote(null);
    try {
      const found = await geocodeAddress(q);
      if (found.latitude === null || found.longitude === null) {
        setLocationNote(found.geocoder === 'stub'
          ? 'No address lookup is configured on this server. Click the map to place the pin by hand.'
          : 'That address was not found. Check the spelling, or click the map to place the pin by hand.');
        return;
      }
      setPin_(found.latitude, found.longitude);
      setLocationNote(`Found: ${found.formattedAddress}`);
    } catch (err) {
      setLocationNote(err instanceof Error ? err.message : 'The address lookup failed.');
    } finally {
      setLocating(false);
    }
  }

  // -------------------------------------------------------------------
  // Documents
  // -------------------------------------------------------------------

  /**
   * Upload one chosen file and remember where it landed.
   *
   * A failure is reported on the document itself rather than thrown: four
   * documents are collected on this step and one that would not upload should
   * say so next to its own button, leaving the other three attached.
   */
  function pickFile(
    set: (fn: (d: DocState) => DocState) => void,
  ) {
    return async (file: File | undefined, category: DocCategory, fieldKey: string) => {
      if (!file) return;
      set((d) => ({ ...d, uploading: true, error: null }));
      clearError(fieldKey);
      try {
        const url = await uploadProviderDocument(file, category);
        set((d) => ({ ...d, url, fileName: file.name, uploading: false }));
      } catch (err) {
        set((d) => ({
          ...d,
          uploading: false,
          error: err instanceof Error ? err.message : 'That file could not be uploaded.',
        }));
      }
    };
  }

  /** Patch one document's validity dates. */
  const docDates = (set: (fn: (d: DocState) => DocState) => void) =>
    (patch: Partial<Pick<DocState, 'validFrom' | 'validTo'>>) => set((d) => ({ ...d, ...patch }));

  // -------------------------------------------------------------------
  // Moving between steps
  // -------------------------------------------------------------------

  /**
   * What stops this step being finished.
   *
   * Presence, and the two formats worth catching before a round trip. Everything
   * else — the rate band, the PIN rules, the GST checksum, whether the police
   * verification has expired — is the server's, and is reported by
   * `applyServerFields` on submit.
   */
  function localGaps(forStep: number): Record<string, string> {
    const e: Record<string, string> = {};
    if (forStep === 0) {
      if (name.trim().length < 2) e.name = isOrg ? 'Enter the organisation name.' : 'Enter their full name.';
      if (isOrg && contactPerson.trim().length < 2) {
        e.contactPerson = 'Enter the name of the person Sathiyaa should speak to.';
      }
      if (!/^[6-9]\d{9}$/.test(mobile.trim())) {
        e.mobile = 'Enter a 10-digit Indian mobile number starting 6-9.';
      }
      if (!isOrg && !gender) e.gender = 'Choose male, female or other.';
    }
    if (forStep === 1) {
      if (line1.trim().length < 6) {
        e.address = isOrg ? 'Enter the registered office address.' : 'Enter their home address.';
      }
      if (lat === null || lng === null) {
        e.location = 'Find the address on the map, or click the map, so the location is set. '
          + 'Without it this provider appears in no customer search.';
      }
      if (!isOrg && days.size === 0) e.workHours = 'Pick at least one working day.';
      if (services.size === 0) e.expertise = 'Pick at least one service they provide.';
    }
    if (forStep === 2) {
      if (!noFees && rate.trim() === '') {
        e.hourlyRate = 'Enter an hourly rate, or mark this as donated time.';
      }
      if (languages.size === 0) {
        e.languages = 'Pick at least one language. A carer with none is matched by no language search.';
      }
    }
    if (forStep === 3) {
      if (!isOrg) {
        if (!aadhar.url) e.aadharDocUrl = 'Attach an Aadhaar card or a work certificate.';
        if (!police.url) e.policeVerificationUrl = 'Attach the police verification certificate.';
        else if (!police.validFrom || !police.validTo) {
          e.policeVerificationDates = 'Enter the dates it is valid between.';
        }
        if (clinical && !medical.url) {
          e.medicalCertificateUrl = 'A medical certificate is required for nursing and physiotherapy.';
        }
        if (medical.url && (!medical.validFrom || !medical.validTo)) {
          e.medicalCertificateDates = 'Enter the dates it is valid between.';
        }
      }
    }
    if (forStep === 4) {
      if (!/^\d{6}$/.test(pin.trim())) e.pin = 'The PIN must be exactly 6 digits.';
    }
    return e;
  }

  function next() {
    const gaps = localGaps(step);
    if (Object.keys(gaps).length > 0) {
      setErrors(gaps);
      return;
    }
    setErrors({});
    setBanner(null);
    if (step < lastStep) setStep(step + 1);
    else void submit();
  }

  /**
   * Show the server's field errors where they belong, and go to the first of
   * them. Anything whose name this form does not recognise is shown as a banner
   * rather than dropped, so drift between the two sides is visible.
   */
  function applyServerFields(fields: Record<string, string>) {
    setErrors(fields);
    const steps = Object.keys(fields).map((k) => FIELD_STEP[k]).filter((s) => s !== undefined);
    const unknown = Object.entries(fields).filter(([k]) => FIELD_STEP[k] === undefined);
    if (steps.length > 0) setStep(Math.min(...steps));
    setBanner(unknown.length > 0
      ? unknown.map(([k, v]) => `${k}: ${v}`).join(' ')
      : 'Some answers need correcting — see the highlighted field.');
  }

  async function submit() {
    setSubmitting(true);
    setBanner(null);
    try {
      const workHours = (isOrg && days.size === 0 ? [] : [...days]).map((d) => ({
        dayOfWeek: d,
        startTime: differentHours ? (perDay[d]?.from ?? from) : from,
        endTime: differentHours ? (perDay[d]?.to ?? to) : to,
      }));

      const payload: NewProviderPayload = {
        providerKind: kind,
        name: name.trim(),
        mobile: mobile.trim(),
        email: email.trim() || undefined,
        pin: pin.trim(),
        languages: [...languages],
        photoUrl: photo.url,
        address: {
          line1: line1.trim(),
          line2: line2.trim() || undefined,
          city: city.trim() || undefined,
          state: stateName.trim() || undefined,
          pincode: pincode.trim() || undefined,
          latitude: lat,
          longitude: lng,
        },
        workHours,
        expertise: [...services],
        approvalStatus,
        registrationFeePaid: feePaid,
        noFees,
        hourlyRate: noFees ? 0 : Number(rate),
        // A company has neither, and sending an empty gender would be rejected
        // by the column rather than ignored.
        ...(isOrg ? {} : { gender, dob: dob || null }),
        ...(isOrg
          ? {
            contactPerson: contactPerson.trim(),
            gstNumber: gst.trim() || undefined,
            orgRegistrationUrl: orgCert.url,
            allocateViaOrg,
          }
          : {
            aadharDocUrl: aadhar.url,
            policeVerificationUrl: police.url,
            policeVerificationValidFrom: police.validFrom || null,
            policeVerificationValidTo: police.validTo || null,
            medicalCertificateUrl: medical.url,
            medicalCertificateValidFrom: medical.validFrom || null,
            medicalCertificateValidTo: medical.validTo || null,
          }),
      };

      const result = await createProvider(payload);
      onCreated(result, pin.trim());
    } catch (err) {
      const fields = (err as { fields?: Record<string, string> } | undefined)?.fields
        ?? (err as any)?.response?.data?.error?.fields;
      if (fields && typeof fields === 'object') applyServerFields(fields);
      else if (err instanceof ApiRequestError) setBanner(err.message);
      else setBanner(err instanceof Error ? err.message : 'The provider could not be created.');
    } finally {
      setSubmitting(false);
    }
  }

  // -------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------

  const Err = ({ k }: { k: string }) => <FieldError errors={errors} name={k} />;

  /** The props every DocField on this step shares. */
  const docProps = (set: (fn: (d: DocState) => DocState) => void) => ({
    errors,
    clearError,
    onPick: pickFile(set),
    onDates: docDates(set),
  });

  return (
    <Modal onClose={onClose} width={760} dismissOnBackdrop={false}>
      <div style={{ padding: '22px 24px 0' }}>
        <h3 style={{ margin: '0 0 4px', fontSize: 17, fontWeight: 700 }}>Add a service provider</h3>
        <p style={{ margin: '0 0 16px', fontSize: 13, color: 'var(--color-text-muted)', lineHeight: 1.5 }}>
          Creates the account and its sign-in. They can sign in to the provider app straight away on
          their own handset — the account is not tied to this computer.
        </p>

        {/* The stepper, so it is obvious how much is left and what was asked. */}
        <div style={{ display: 'flex', gap: 6, marginBottom: 18, flexWrap: 'wrap' }}>
          {titles.map((t, i) => (
            <div
              key={t}
              style={{
                flex: '1 1 110px',
                padding: '7px 10px',
                borderRadius: 7,
                fontSize: 12,
                fontWeight: i === step ? 700 : 500,
                textAlign: 'center',
                background: i === step ? 'var(--color-primary-light)' : '#f2f4f7',
                color: i === step ? 'var(--color-primary-dark)'
                  : i < step ? 'var(--color-success)' : 'var(--color-text-muted)',
                border: `1px solid ${i === step ? 'var(--color-primary)' : 'transparent'}`,
              }}
            >
              {i < step ? '✓ ' : `${i + 1}. `}{t}
            </div>
          ))}
        </div>

        {banner && <InlineBanner kind="error">{banner}</InlineBanner>}
      </div>

      <div style={{ padding: '0 24px', maxHeight: '58vh', overflowY: 'auto' }}>
        {/* ---------------------------------------------------------- 0 */}
        {step === 0 && (
          <>
            <label className="field-label">What is this account for?</label>
            <div style={{ display: 'flex', gap: 10, marginBottom: 6 }}>
              <Toggle on={!isOrg} onClick={() => { setKind('freelancer'); setErrors({}); }}>
                A freelance carer
              </Toggle>
              <Toggle on={isOrg} onClick={() => { setKind('organization'); setErrors({}); }}>
                An organisation
              </Toggle>
            </div>
            <div className="field-hint" style={{ marginBottom: 18 }}>
              {isOrg
                ? 'An agency. It is verified by its registration, not by an Aadhaar card or a police '
                  + 'check — those belong to the carers it sends, and are collected when the agency '
                  + 'adds each one in the provider app.'
                : 'One person who takes bookings directly. Their own Aadhaar card and police '
                  + 'verification are required before they can be approved.'}
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
              <div>
                <label className="field-label">{isOrg ? 'Organisation name' : 'Full name'}</label>
                <input
                  className={`input ${errors.name ? 'err' : ''}`}
                  value={name}
                  onChange={(e) => { setName(e.target.value); clearError('name'); }}
                  placeholder={isOrg ? 'e.g. Sunrise Elder Care Services' : 'e.g. Priya Shah'}
                />
                <Err k="name" />
              </div>
              {isOrg ? (
                <div>
                  <label className="field-label">Person to speak to</label>
                  <input
                    className={`input ${errors.contactPerson ? 'err' : ''}`}
                    value={contactPerson}
                    onChange={(e) => { setContactPerson(e.target.value); clearError('contactPerson'); }}
                    placeholder="Who answers the phone"
                  />
                  <Err k="contactPerson" />
                </div>
              ) : (
                <div>
                  <label className="field-label">Gender</label>
                  <select
                    className={`input ${errors.gender ? 'err' : ''}`}
                    value={gender}
                    onChange={(e) => { setGender(e.target.value as Gender); clearError('gender'); }}
                  >
                    <option value="female">Female</option>
                    <option value="male">Male</option>
                    <option value="other">Other</option>
                  </select>
                  <div className="field-hint">
                    Families often ask for a particular gender, and a blank here means this carer
                    appears in none of those searches.
                  </div>
                  <Err k="gender" />
                </div>
              )}
              <div>
                <label className="field-label">Mobile number</label>
                <input
                  className={`input ${errors.mobile ? 'err' : ''}`}
                  value={mobile}
                  inputMode="numeric"
                  maxLength={10}
                  onChange={(e) => { setMobile(e.target.value.replace(/\D/g, '')); clearError('mobile'); }}
                  placeholder="10 digits"
                />
                <div className="field-hint">This is what they sign in with. It cannot be changed later from here.</div>
                <Err k="mobile" />
              </div>
              <div>
                <label className="field-label">Email <span style={{ fontWeight: 400 }}>(optional)</span></label>
                <input
                  className={`input ${errors.email ? 'err' : ''}`}
                  value={email}
                  onChange={(e) => { setEmail(e.target.value); clearError('email'); }}
                  placeholder="name@example.com"
                />
                <Err k="email" />
              </div>
              {!isOrg && (
                <div>
                  <label className="field-label">Date of birth <span style={{ fontWeight: 400 }}>(optional)</span></label>
                  <input
                    type="date"
                    className={`input ${errors.dob ? 'err' : ''}`}
                    value={dob}
                    onChange={(e) => { setDob(e.target.value); clearError('dob'); }}
                  />
                  <Err k="dob" />
                </div>
              )}
            </div>
          </>
        )}

        {/* ---------------------------------------------------------- 1 */}
        {step === 1 && (
          <>
            <label className="field-label">{isOrg ? 'Registered office address' : 'Home address'}</label>
            <input
              className={`input ${errors.address ? 'err' : ''}`}
              value={line1}
              onChange={(e) => { setLine1(e.target.value); clearError('address'); }}
              placeholder="House or flat, street, area"
            />
            <Err k="address" />
            <input
              className="input"
              style={{ marginTop: 10 }}
              value={line2}
              onChange={(e) => setLine2(e.target.value)}
              placeholder="Landmark (optional)"
            />
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 12, marginTop: 10 }}>
              <input className="input" value={city} onChange={(e) => setCity(e.target.value)} placeholder="City" />
              <input className="input" value={stateName} onChange={(e) => setStateName(e.target.value)} placeholder="State" />
              <input
                className="input"
                value={pincode}
                inputMode="numeric"
                maxLength={6}
                onChange={(e) => setPincode(e.target.value.replace(/\D/g, ''))}
                placeholder="Pincode"
              />
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '14px 0 8px', flexWrap: 'wrap' }}>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => void findOnMap()} disabled={locating}>
                {locating ? 'Looking up…' : 'Find on map'}
              </button>
              <span className="field-hint" style={{ margin: 0 }}>
                {lat !== null && lng !== null
                  ? `Pin at ${lat}, ${lng}`
                  : 'No location set yet — required, or this provider appears in no search.'}
              </span>
            </div>
            {locationNote && <div className="field-hint" style={{ marginBottom: 8 }}>{locationNote}</div>}
            <div
              ref={mapHost}
              style={{
                height: 260, borderRadius: 10, border: `1px solid ${errors.location ? 'var(--color-danger)' : 'var(--color-border)'}`,
                marginBottom: 4, overflow: 'hidden',
              }}
            />
            <Err k="location" />

            <div style={{ marginTop: 20 }}>
              <label className="field-label">
                {isOrg ? 'Days the organisation operates (optional)' : 'Working days'}
              </label>
              {isOrg && (
                <div className="field-hint" style={{ marginBottom: 6 }}>
                  Leave all of them unticked and the agency is treated as covering every day — an
                  agency covers whatever hours the carer it sends covers, and each carer's own days
                  are collected when the agency adds them.
                </div>
              )}
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 10 }}>
                {DAYS.map((d) => (
                  <Toggle
                    key={d}
                    on={days.has(d)}
                    onClick={() => {
                      const next = new Set(days);
                      if (next.has(d)) next.delete(d); else next.add(d);
                      setDays(next);
                      clearError('workHours');
                    }}
                  >
                    {DAY_LABELS[d]}
                  </Toggle>
                ))}
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                <div>
                  <label className="field-label">Usual start</label>
                  <input type="time" className={`input ${errors.workHours ? 'err' : ''}`} value={from}
                    onChange={(e) => { setFrom(e.target.value); clearError('workHours'); }} />
                </div>
                <div>
                  <label className="field-label">Usual finish</label>
                  <input type="time" className={`input ${errors.workHours ? 'err' : ''}`} value={to}
                    onChange={(e) => { setTo(e.target.value); clearError('workHours'); }} />
                </div>
              </div>
              <Err k="workHours" />
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10, fontSize: 13 }}>
                <input type="checkbox" checked={differentHours} onChange={(e) => setDifferentHours(e.target.checked)} />
                Some days have different hours
              </label>
              {differentHours && (
                <div style={{ marginTop: 10, display: 'grid', gap: 8 }}>
                  {[...days].map((d) => (
                    <div key={d} style={{ display: 'grid', gridTemplateColumns: '60px 1fr 1fr', gap: 10, alignItems: 'center' }}>
                      <span style={{ fontSize: 13, fontWeight: 600 }}>{DAY_LABELS[d]}</span>
                      <input
                        type="time" className="input"
                        value={perDay[d]?.from ?? from}
                        onChange={(e) => setPerDay({ ...perDay, [d]: { from: e.target.value, to: perDay[d]?.to ?? to } })}
                      />
                      <input
                        type="time" className="input"
                        value={perDay[d]?.to ?? to}
                        onChange={(e) => setPerDay({ ...perDay, [d]: { from: perDay[d]?.from ?? from, to: e.target.value } })}
                      />
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div style={{ marginTop: 20 }}>
              <label className="field-label">Services provided</label>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                {SERVICES.map((s) => (
                  <Toggle
                    key={s}
                    on={services.has(s)}
                    onClick={() => {
                      const next = new Set(services);
                      if (next.has(s)) next.delete(s); else next.add(s);
                      setServices(next);
                      clearError('expertise');
                    }}
                  >
                    {SERVICE_TYPE_LABELS[s]}
                  </Toggle>
                ))}
              </div>
              <Err k="expertise" />
            </div>
          </>
        )}

        {/* ---------------------------------------------------------- 2 */}
        {step === 2 && (
          <>
            {!isOrg && (
              <label style={{ display: 'flex', gap: 10, alignItems: 'flex-start', marginBottom: 16, fontSize: 13.5 }}>
                <input type="checkbox" checked={noFees} style={{ marginTop: 3 }}
                  onChange={(e) => { setNoFees(e.target.checked); clearError('hourlyRate'); }} />
                <span>
                  <strong>They are giving their time free.</strong>
                  <div className="field-hint">
                    No hourly rate is charged and the hours are credited to their Time Bank instead.
                  </div>
                </span>
              </label>
            )}
            {!noFees && (
              <div style={{ maxWidth: 280 }}>
                <label className="field-label">{isOrg ? 'Standard hourly rate' : 'Hourly rate'} (₹)</label>
                <input
                  className={`input ${errors.hourlyRate ? 'err' : ''}`}
                  value={rate}
                  inputMode="decimal"
                  onChange={(e) => { setRate(e.target.value.replace(/[^\d.]/g, '')); clearError('hourlyRate'); }}
                  placeholder="e.g. 320"
                />
                <div className="field-hint">Between ₹50 and ₹5,000 an hour.</div>
                <Err k="hourlyRate" />
              </div>
            )}

            <div style={{ marginTop: 22 }}>
              <label className="field-label">Languages spoken</label>
              <div className="field-hint" style={{ marginBottom: 8 }}>
                Families filter on this and it is printed on every result card, so it has to be what
                they actually speak rather than the English-only default.
              </div>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                {LANGUAGES.map((l) => (
                  <Toggle
                    key={l}
                    on={languages.has(l)}
                    onClick={() => {
                      const next = new Set(languages);
                      if (next.has(l)) next.delete(l); else next.add(l);
                      setLanguages(next);
                      clearError('languages');
                    }}
                  >
                    {l}
                  </Toggle>
                ))}
              </div>
              <Err k="languages" />
            </div>
          </>
        )}

        {/* ---------------------------------------------------------- 3 */}
        {step === 3 && (isOrg ? (
          <>
            <DocField
              label="Registration certificate"
              hint="Certificate of incorporation, shops-and-establishment licence, society or trust
                    registration — whatever this organisation is registered as. The name on it must
                    match the organisation name entered. It can be added later from their profile."
              doc={orgCert} category="org-registration" fieldKey="orgRegistrationUrl" {...docProps(setOrgCert)}
            />
            <div style={{ maxWidth: 320 }}>
              <label className="field-label">GST number <span style={{ fontWeight: 400 }}>(optional)</span></label>
              <input
                className={`input ${errors.gstNumber ? 'err' : ''}`}
                value={gst}
                maxLength={15}
                onChange={(e) => { setGst(e.target.value.toUpperCase()); clearError('gstNumber'); }}
                placeholder="e.g. 24ABCDE1234F1Z5"
              />
              <div className="field-hint">Organisations below the threshold do not have one.</div>
              <Err k="gstNumber" />
            </div>
            <DocField
              label="Logo or photo (optional)"
              hint="Shown on the organisation's card in the customer app."
              doc={photo} category="photo" fieldKey="photoUrl" {...docProps(setPhoto)}
            />
          </>
        ) : (
          <>
            <DocField
              label="Aadhaar or work certificate"
              hint="Either side, as long as the name and photograph are readable."
              doc={aadhar} category="aadhar" fieldKey="aadharDocUrl" {...docProps(setAadhar)}
            />
            <DocField
              label="Police verification"
              hint="The certificate from their local station. The dates on it are needed as well."
              doc={police} category="police-verification"
              fieldKey="policeVerificationUrl" dates datesKey="policeVerificationDates" {...docProps(setPolice)}
            />
            <DocField
              label={`Medical certificate${clinical ? '' : ' (optional)'}`}
              hint={clinical
                ? 'Required, because this carer provides nursing or physiotherapy.'
                : 'Only required for nursing and physiotherapy.'}
              doc={medical} category="medical-certificate"
              fieldKey="medicalCertificateUrl" dates datesKey="medicalCertificateDates" {...docProps(setMedical)}
            />
            <DocField
              label="Photograph (optional)"
              hint="Shown on their card in the customer app, and used for the start-of-service check."
              doc={photo} category="photo" fieldKey="photoUrl" {...docProps(setPhoto)}
            />
          </>
        ))}

        {/* ---------------------------------------------------------- 4 */}
        {step === 4 && (
          <>
            <label className="field-label">Sign-in PIN</label>
            <div className="field-hint" style={{ marginBottom: 8 }}>
              Six digits, used with the mobile number above. It is stored hashed and cannot be read
              back, so write it down or pass it on before closing the confirmation — it is shown once.
              They can change it from the app at any time.
            </div>
            <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
              <input
                className={`input ${errors.pin ? 'err' : ''}`}
                style={{ maxWidth: 160, letterSpacing: '0.3em', fontSize: 16 }}
                value={pin}
                inputMode="numeric"
                maxLength={6}
                onChange={(e) => { setPin(e.target.value.replace(/\D/g, '')); clearError('pin'); }}
                placeholder="------"
              />
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => { setPin(generatePin()); clearError('pin'); }}>
                Generate
              </button>
            </div>
            <Err k="pin" />

            <div style={{ marginTop: 24 }}>
              <label className="field-label">Approval</label>
              <div className="field-hint" style={{ marginBottom: 8 }}>
                Only an approved provider appears in customer search. Choose Pending if somebody else
                still has to look at the documents.
              </div>
              <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                {(['approved', 'pending', 'hold'] as ApprovalStatus[]).map((s) => (
                  <Toggle key={s} on={approvalStatus === s} onClick={() => setApprovalStatus(s)}>
                    {s === 'approved' ? 'Approved now' : s === 'pending' ? 'Pending review' : 'On hold'}
                  </Toggle>
                ))}
              </div>
            </div>

            <label style={{ display: 'flex', gap: 10, alignItems: 'flex-start', marginTop: 20, fontSize: 13.5 }}>
              <input type="checkbox" checked={feePaid} style={{ marginTop: 3 }} onChange={(e) => setFeePaid(e.target.checked)} />
              <span>
                <strong>The registration fee has been collected.</strong>
                <div className="field-hint">
                  Tick this when the office has taken it in cash or by transfer. Nothing is charged
                  through the payment gateway from here.
                </div>
              </span>
            </label>

            {isOrg && (
              <label style={{ display: 'flex', gap: 10, alignItems: 'flex-start', marginTop: 16, fontSize: 13.5 }}>
                <input type="checkbox" checked={allocateViaOrg} style={{ marginTop: 3 }}
                  onChange={(e) => setAllocateViaOrg(e.target.checked)} />
                <span>
                  <strong>Bookings go to the organisation, not to individual carers.</strong>
                  <div className="field-hint">
                    Families see the agency in search and the agency decides which of its carers to
                    send. Untick it to have each carer appear and be booked in their own right.
                  </div>
                </span>
              </label>
            )}
          </>
        )}
      </div>

      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        gap: 10, padding: '16px 24px 22px', marginTop: 8, borderTop: '1px solid var(--color-border)',
      }}>
        <button className="btn btn-secondary" onClick={onClose} disabled={submitting}>Cancel</button>
        <div style={{ display: 'flex', gap: 10 }}>
          {step > 0 && (
            <button className="btn btn-secondary" onClick={() => { setStep(step - 1); setBanner(null); }} disabled={submitting}>
              Back
            </button>
          )}
          <button className="btn btn-primary" onClick={next} disabled={submitting}>
            {submitting ? 'Creating…' : step === lastStep ? 'Create provider' : 'Next'}
          </button>
        </div>
      </div>
    </Modal>
  );
}

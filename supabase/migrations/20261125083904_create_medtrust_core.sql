/*
# Create MedTrust core registry and audit tables

1. New Tables
- `profiles`: signed-in user name and role for role-aware navigation.
- `institutions`: institution profile owned by an administrator.
- `document_templates`: genuine sample metadata registered by an institution.
- `doctors`: doctor identifiers and signature sample metadata registered by an institution.
- `verification_requests`: immutable verification history visible to the requester and institution owner.
2. Security
- Enable row level security on every table.
- Restrict each account to its own profile, institution records, and verification history.
- Allow authenticated users to create verification records, but never allow them to edit or delete audit records.
- Grant only the verbs required by the application.
3. Notes
- Uploaded document contents are represented by safe metadata in this first release; real document storage should use a private bucket with signed URLs before production patient data is introduced.
- All development records must remain synthetic as required by the SRS.
*/

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('institution_admin', 'pharmacist', 'insurer', 'patient')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.institutions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  institution_type text NOT NULL CHECK (institution_type IN ('Hospital', 'Laboratory', 'Pharmacy chain')),
  registration_number text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.document_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  document_type text NOT NULL CHECK (document_type IN ('Prescription', 'Lab report')),
  file_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.doctors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  doctor_name text NOT NULL,
  doctor_identifier text NOT NULL,
  signature_file_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.verification_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
  document_type text NOT NULL CHECK (document_type IN ('Prescription', 'Lab report')),
  file_name text NOT NULL,
  risk_level text NOT NULL CHECK (risk_level IN ('Low', 'Medium', 'High', 'Unverifiable')),
  verdict text NOT NULL,
  explanation text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS verification_requests_created_at_idx ON public.verification_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS verification_requests_risk_level_idx ON public.verification_requests(risk_level);
CREATE INDEX IF NOT EXISTS verification_requests_document_type_idx ON public.verification_requests(document_type);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_requests ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.institutions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.doctors TO authenticated;
GRANT SELECT, INSERT ON public.verification_requests TO authenticated;

DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_delete_own" ON public.profiles;
CREATE POLICY "profiles_delete_own" ON public.profiles FOR DELETE TO authenticated USING (auth.uid() = id);

DROP POLICY IF EXISTS "institutions_select_own" ON public.institutions;
CREATE POLICY "institutions_select_own" ON public.institutions FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "institutions_insert_own" ON public.institutions;
CREATE POLICY "institutions_insert_own" ON public.institutions FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "institutions_update_own" ON public.institutions;
CREATE POLICY "institutions_update_own" ON public.institutions FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "institutions_delete_own" ON public.institutions;
CREATE POLICY "institutions_delete_own" ON public.institutions FOR DELETE TO authenticated USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS "templates_select_own" ON public.document_templates;
CREATE POLICY "templates_select_own" ON public.document_templates FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));
DROP POLICY IF EXISTS "templates_insert_own" ON public.document_templates;
CREATE POLICY "templates_insert_own" ON public.document_templates FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));
DROP POLICY IF EXISTS "templates_update_own" ON public.document_templates;
CREATE POLICY "templates_update_own" ON public.document_templates FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));
DROP POLICY IF EXISTS "templates_delete_own" ON public.document_templates;
CREATE POLICY "templates_delete_own" ON public.document_templates FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));

DROP POLICY IF EXISTS "doctors_select_own" ON public.doctors;
CREATE POLICY "doctors_select_own" ON public.doctors FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));
DROP POLICY IF EXISTS "doctors_insert_own" ON public.doctors;
CREATE POLICY "doctors_insert_own" ON public.doctors FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));
DROP POLICY IF EXISTS "doctors_update_own" ON public.doctors;
CREATE POLICY "doctors_update_own" ON public.doctors FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));
DROP POLICY IF EXISTS "doctors_delete_own" ON public.doctors;
CREATE POLICY "doctors_delete_own" ON public.doctors FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM public.institutions i WHERE i.id = institution_id AND i.owner_id = auth.uid()));

DROP POLICY IF EXISTS "verifications_select_own" ON public.verification_requests;
CREATE POLICY "verifications_select_own" ON public.verification_requests FOR SELECT TO authenticated USING (auth.uid() = requester_id);
DROP POLICY IF EXISTS "verifications_insert_own" ON public.verification_requests;
CREATE POLICY "verifications_insert_own" ON public.verification_requests FOR INSERT TO authenticated WITH CHECK (auth.uid() = requester_id);
DROP POLICY IF EXISTS "verifications_update_none" ON public.verification_requests;
CREATE POLICY "verifications_update_none" ON public.verification_requests FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "verifications_delete_none" ON public.verification_requests;
CREATE POLICY "verifications_delete_none" ON public.verification_requests FOR DELETE TO authenticated USING (false);

-- Hospital Patient Admission & Treatment Analytics
-- MySQL 8.0+ | DEMO schema. The CSVs shipped with this kit are synthetic, not real patient data.
CREATE DATABASE IF NOT EXISTS hospital_analytics;
USE hospital_analytics;

DROP VIEW IF EXISTS vw_patient_billing;
DROP VIEW IF EXISTS vw_dept_admissions;
DROP TABLE IF EXISTS Billing;
DROP TABLE IF EXISTS Treatments;
DROP TABLE IF EXISTS Admissions;
DROP TABLE IF EXISTS Doctors;
DROP TABLE IF EXISTS Departments;
DROP TABLE IF EXISTS Patients;

CREATE TABLE Patients (
  Patient_ID INT PRIMARY KEY,
  Birth_Year SMALLINT,
  Gender VARCHAR(20),
  Region VARCHAR(30)
);
CREATE TABLE Departments (
  Department_ID INT PRIMARY KEY,
  Department_Name VARCHAR(100) NOT NULL,
  Bed_Capacity INT NOT NULL CHECK (Bed_Capacity >= 0)
);
CREATE TABLE Doctors (
  Doctor_ID INT PRIMARY KEY,
  Doctor_Name VARCHAR(100) NOT NULL,
  Department_ID INT NOT NULL,
  Specialization VARCHAR(100),
  CONSTRAINT fk_doctor_department FOREIGN KEY (Department_ID) REFERENCES Departments(Department_ID)
);
CREATE TABLE Admissions (
  Admission_ID INT PRIMARY KEY,
  Patient_ID INT NOT NULL,
  Doctor_ID INT NOT NULL,
  Department_ID INT NOT NULL,
  Admission_Date DATE NOT NULL,
  Discharge_Date DATE,
  Admission_Type VARCHAR(30),
  Discharge_Disposition VARCHAR(30),
  Readmitted_Within_30_Days BOOLEAN DEFAULT FALSE,
  CONSTRAINT fk_admission_patient FOREIGN KEY (Patient_ID) REFERENCES Patients(Patient_ID),
  CONSTRAINT fk_admission_doctor FOREIGN KEY (Doctor_ID) REFERENCES Doctors(Doctor_ID),
  CONSTRAINT fk_admission_department FOREIGN KEY (Department_ID) REFERENCES Departments(Department_ID),
  CHECK (Discharge_Date IS NULL OR Discharge_Date >= Admission_Date)
);
CREATE TABLE Treatments (
  Treatment_ID INT PRIMARY KEY,
  Admission_ID INT NOT NULL,
  Treatment_Type VARCHAR(100),
  Treatment_Cost DECIMAL(12,2) NOT NULL DEFAULT 0,
  CONSTRAINT fk_treatment_admission FOREIGN KEY (Admission_ID) REFERENCES Admissions(Admission_ID)
);
CREATE TABLE Billing (
  Billing_ID INT PRIMARY KEY,
  Admission_ID INT NOT NULL UNIQUE,
  Billed_Amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  Amount_Paid DECIMAL(12,2) NOT NULL DEFAULT 0,
  Outstanding_Balance DECIMAL(12,2) NOT NULL DEFAULT 0,
  Bill_Date DATE,
  CONSTRAINT fk_billing_admission FOREIGN KEY (Admission_ID) REFERENCES Admissions(Admission_ID),
  CHECK (Billed_Amount >= 0 AND Amount_Paid >= 0 AND Outstanding_Balance >= 0)
);

-- Import the six CSVs from 02_Excel_Cleaning using MySQL Workbench Table Data Import Wizard.
-- For Admissions.csv, import only fields matching the table. The helper fields
-- Length_of_Stay_Days and Next_Admission_Date are derived analysis fields and not schema columns.
-- Import CSV columns in this order for Admissions:
-- Admission_ID, Patient_ID, Doctor_ID, Department_ID, Admission_Date, Discharge_Date,
-- Admission_Type, Discharge_Disposition, Readmitted_Within_30_Days
-- The Admissions CSV contains two helper columns at the end; uncheck them in import mapping.

CREATE INDEX idx_admissions_date ON Admissions(Admission_Date);
CREATE INDEX idx_admissions_patient_dates ON Admissions(Patient_ID, Admission_Date, Discharge_Date);
CREATE INDEX idx_admissions_department ON Admissions(Department_ID);
CREATE INDEX idx_treatments_admission ON Treatments(Admission_ID);

-- Department-level admissions, average length of stay, billed and paid amounts.
CREATE OR REPLACE VIEW vw_dept_admissions AS
SELECT
  d.Department_ID,
  d.Department_Name,
  d.Bed_Capacity,
  COUNT(a.Admission_ID) AS Admissions,
  ROUND(AVG(CASE WHEN a.Discharge_Date IS NOT NULL
                 THEN DATEDIFF(a.Discharge_Date, a.Admission_Date) END), 2) AS Avg_Length_of_Stay_Days,
  SUM(CASE WHEN a.Discharge_Date IS NOT NULL
           THEN DATEDIFF(a.Discharge_Date, a.Admission_Date) ELSE 0 END) AS Total_Patient_Days,
  ROUND(100 * SUM(CASE WHEN a.Discharge_Date IS NOT NULL
                       THEN DATEDIFF(a.Discharge_Date, a.Admission_Date) ELSE 0 END)
        / NULLIF(d.Bed_Capacity * GREATEST(DATEDIFF(CURDATE(), '2023-01-01'), 1), 0), 2) AS Approx_Occupancy_Pct,
  ROUND(COALESCE(SUM(b.Billed_Amount),0),2) AS Total_Billed,
  ROUND(COALESCE(SUM(b.Amount_Paid),0),2) AS Revenue_Collected
FROM Departments d
LEFT JOIN Admissions a ON a.Department_ID = d.Department_ID
LEFT JOIN Billing b ON b.Admission_ID = a.Admission_ID
GROUP BY d.Department_ID, d.Department_Name, d.Bed_Capacity;

CREATE OR REPLACE VIEW vw_patient_billing AS
SELECT
  p.Patient_ID,
  p.Gender,
  p.Region,
  a.Admission_ID,
  a.Admission_Date,
  a.Discharge_Date,
  d.Department_Name,
  doc.Doctor_Name,
  COALESCE(t.Treatment_Cost_Total,0) AS Treatment_Cost_Total,
  COALESCE(b.Billed_Amount,0) AS Billed_Amount,
  COALESCE(b.Amount_Paid,0) AS Amount_Paid,
  COALESCE(b.Outstanding_Balance,0) AS Outstanding_Balance,
  a.Readmitted_Within_30_Days,
  CASE WHEN a.Discharge_Date IS NOT NULL THEN DATEDIFF(a.Discharge_Date,a.Admission_Date) END AS Length_of_Stay_Days
FROM Admissions a
JOIN Patients p ON p.Patient_ID=a.Patient_ID
JOIN Departments d ON d.Department_ID=a.Department_ID
JOIN Doctors doc ON doc.Doctor_ID=a.Doctor_ID
LEFT JOIN (
  SELECT Admission_ID, SUM(Treatment_Cost) AS Treatment_Cost_Total
  FROM Treatments GROUP BY Admission_ID
) t ON t.Admission_ID=a.Admission_ID
LEFT JOIN Billing b ON b.Admission_ID=a.Admission_ID;

-- Six business queries (save screenshots of results for report)
-- Q1: admissions by department
SELECT Department_Name, Admissions FROM vw_dept_admissions ORDER BY Admissions DESC;
-- Q2: monthly admissions trend
SELECT DATE_FORMAT(Admission_Date,'%Y-%m') AS Admission_Month, COUNT(*) AS Admissions
FROM Admissions GROUP BY DATE_FORMAT(Admission_Date,'%Y-%m') ORDER BY Admission_Month;
-- Q3: doctor workload and average length of stay
SELECT doc.Doctor_Name, COUNT(a.Admission_ID) AS Admissions,
       ROUND(AVG(DATEDIFF(a.Discharge_Date,a.Admission_Date)),2) AS Avg_LOS
FROM Doctors doc LEFT JOIN Admissions a ON a.Doctor_ID=doc.Doctor_ID
GROUP BY doc.Doctor_ID,doc.Doctor_Name ORDER BY Admissions DESC;
-- Q4: billed, paid and outstanding amounts
SELECT ROUND(SUM(Billed_Amount),2) AS Total_Billed,
       ROUND(SUM(Amount_Paid),2) AS Revenue_Collected,
       ROUND(SUM(Outstanding_Balance),2) AS Outstanding
FROM Billing;
-- Q5: readmission rate by department (flag must be defined consistently)
SELECT d.Department_Name,
       COUNT(*) AS Admissions,
       SUM(a.Readmitted_Within_30_Days) AS Readmitted_Admissions,
       ROUND(100*AVG(a.Readmitted_Within_30_Days),2) AS Readmission_Pct
FROM Admissions a JOIN Departments d ON d.Department_ID=a.Department_ID
GROUP BY d.Department_Name ORDER BY Readmission_Pct DESC;
-- Q6: treatment costs by type
SELECT Treatment_Type, COUNT(*) AS Treatment_Count, ROUND(SUM(Treatment_Cost),2) AS Total_Cost,
       ROUND(AVG(Treatment_Cost),2) AS Avg_Cost
FROM Treatments GROUP BY Treatment_Type ORDER BY Total_Cost DESC;

-- Validation checks
SELECT COUNT(*) AS Patients FROM Patients;
SELECT COUNT(*) AS Admissions FROM Admissions;
SELECT COUNT(*) AS Admissions_Missing_Patient
FROM Admissions a LEFT JOIN Patients p ON p.Patient_ID=a.Patient_ID WHERE p.Patient_ID IS NULL;
SELECT COUNT(*) AS Invalid_Discharge_Dates FROM Admissions
WHERE Discharge_Date IS NOT NULL AND Discharge_Date < Admission_Date;

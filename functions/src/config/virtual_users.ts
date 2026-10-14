/**
 * Authoritative Virtual User Account Definitions
 *
 * 20 Deterministic Synthetic Kenyan Student Uploader Accounts
 * Reuses verified existing accounts; never creates duplicates.
 */

export interface VirtualUserAccount {
  userIndex: number;
  name: string;
  email: string;
  uid: string;
  role: string;
}

export const VIRTUAL_USER_ACCOUNTS: readonly VirtualUserAccount[] = [
  {
    userIndex: 1,
    name: "Brian Kiprop",
    email: "brian.kiprop@virtual.mirrorlaikipia.ac.ke",
    uid: "QtGeH4iJPsefnOTXwzht9K4U1Wz2",
    role: "Student",
  },
  {
    userIndex: 2,
    name: "Faith Wanjiku",
    email: "faith.wanjiku@virtual.mirrorlaikipia.ac.ke",
    uid: "JCcKOBFIoiMAc30OZZnMmZjlDfC2",
    role: "Student",
  },
  {
    userIndex: 3,
    name: "Evans Omondi",
    email: "evans.omondi@virtual.mirrorlaikipia.ac.ke",
    uid: "QsA6ad6epNa4cgwyd47SuBiN6463",
    role: "Student",
  },
  {
    userIndex: 4,
    name: "Mercy Cherono",
    email: "mercy.cherono@virtual.mirrorlaikipia.ac.ke",
    uid: "HFIkJfoFy4T2zTXOaVnglbhDVZs1",
    role: "Student",
  },
  {
    userIndex: 5,
    name: "Kevin Mutua",
    email: "kevin.mutua@virtual.mirrorlaikipia.ac.ke",
    uid: "OOIpYAZif4XYkxKpFhf51aUDBnx1",
    role: "Student",
  },
  {
    userIndex: 6,
    name: "Sharon Chebet",
    email: "sharon.chebet@virtual.mirrorlaikipia.ac.ke",
    uid: "M0KLrn7NOnbi0dWrZfaq7VEjVMA2",
    role: "Student",
  },
  {
    userIndex: 7,
    name: "Denis Kamau",
    email: "denis.kamau@virtual.mirrorlaikipia.ac.ke",
    uid: "bP4ZXUDtx8Z67FI3LVSdYQIN2gB2",
    role: "Student",
  },
  {
    userIndex: 8,
    name: "Brenda Akinyi",
    email: "brenda.akinyi@virtual.mirrorlaikipia.ac.ke",
    uid: "OQWu4felHWVJxg39dJG79NboZdO2",
    role: "Student",
  },
  {
    userIndex: 9,
    name: "Collins Kipkoech",
    email: "collins.kipkoech@virtual.mirrorlaikipia.ac.ke",
    uid: "YEQ41WnN7KRxHt9ZY1bPNEbYdb83",
    role: "Student",
  },
  {
    userIndex: 10,
    name: "Cynthia Nyambura",
    email: "cynthia.nyambura@virtual.mirrorlaikipia.ac.ke",
    uid: "Aq5m9sSDo4d5wyWN0PmxwlNwM9R2",
    role: "Student",
  },
  {
    userIndex: 11,
    name: "Victor Ochieng",
    email: "victor.ochieng@virtual.mirrorlaikipia.ac.ke",
    uid: "CYa7vinMoMT676WsnlAzZTrTdlv1",
    role: "Student",
  },
  {
    userIndex: 12,
    name: "Beatrice Jebet",
    email: "beatrice.jebet@virtual.mirrorlaikipia.ac.ke",
    uid: "dokySdJ0UobKWw7w4VyQFbc9IO33",
    role: "Student",
  },
  {
    userIndex: 13,
    name: "Ian Mwangi",
    email: "ian.mwangi@virtual.mirrorlaikipia.ac.ke",
    uid: "uIUh5LJJBab56crNWbA7ORKYgMq1",
    role: "Student",
  },
  {
    userIndex: 14,
    name: "Joyce Wairimu",
    email: "joyce.wairimu@virtual.mirrorlaikipia.ac.ke",
    uid: "qOYcPHkQGcVmh5j7SKZHArXkTe02",
    role: "Student",
  },
  {
    userIndex: 15,
    name: "Samuel Kiptoo",
    email: "samuel.kiptoo@virtual.mirrorlaikipia.ac.ke",
    uid: "QTVtApGAclWYGs1Xr8nYPxoeBL02",
    role: "Student",
  },
  {
    userIndex: 16,
    name: "Vivian Achieng",
    email: "vivian.achieng@virtual.mirrorlaikipia.ac.ke",
    uid: "IohG9z1xQ5at4QNRBAMqB2c6ow43",
    role: "Student",
  },
  {
    userIndex: 17,
    name: "Dennis Maina",
    email: "dennis.maina@virtual.mirrorlaikipia.ac.ke",
    uid: "YioMpapf80XzGRf90hQ3uu2rdB32",
    role: "Student",
  },
  {
    userIndex: 18,
    name: "Caroline Muthoni",
    email: "caroline.muthoni@virtual.mirrorlaikipia.ac.ke",
    uid: "k8tJKILTmVTYuE51JkVSJSwEFCm2",
    role: "Student",
  },
  {
    userIndex: 19,
    name: "Edwin Koech",
    email: "edwin.koech@virtual.mirrorlaikipia.ac.ke",
    uid: "8zemvGHaije0peRyEOzeXwf8AFC3",
    role: "Student",
  },
  {
    userIndex: 20,
    name: "Ruth Njeri",
    email: "ruth.njeri@virtual.mirrorlaikipia.ac.ke",
    uid: "OOxEWlz2v4ceWqzG49V4IJ51OVn1",
    role: "Student",
  },
] as const;

/// Correos de Google que entran como ADMINISTRADOR.
/// Cualquier otra cuenta de Google entra como usuario normal.
const adminEmails = <String>{
  'alexalvarado0115@gmail.com',
  'romeroeve0905@gmail.com',
  'alexis.bad.trejo@gmail.com',
  'fdb2330910@gmail.com', 
  'florm97847@gmail.com',    
};

bool isAdminEmail(String? email) =>
    email != null && adminEmails.contains(email.trim().toLowerCase());
